use reqwest::{Client, Url};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::VecDeque, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    task::JoinHandle,
    time::Instant,
};

const POLL: Duration = Duration::from_secs(2);

#[derive(Debug, Deserialize)]
struct Request {
    id: u64,
    op: String,
    address: Option<String>,
    volume: Option<u8>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct State {
    status: String,
    title: String,
    artist: String,
    album: String,
    albumart: String,
    volume: Option<u8>,
    disable_volume_control: bool,
    mute: bool,
}

fn address(raw: &str) -> Result<Url, String> {
    let mut url = Url::parse(raw.trim()).map_err(|_| "Invalid HTTP(S) address")?;
    if !matches!(url.scheme(), "http" | "https")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
    {
        return Err("Use an HTTP(S) address without a path or credentials".into());
    }
    url.set_path("/");
    Ok(url)
}

fn state(value: Value, base: &Url) -> Result<State, String> {
    let status = value
        .get("status")
        .and_then(Value::as_str)
        .filter(|s| matches!(*s, "play" | "pause" | "stop"))
        .ok_or("Invalid Volumio response: missing or unknown status")?;
    let text = |key| {
        value
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned()
    };
    let volume = value
        .get("volume")
        .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
        .filter(|v| *v <= 100)
        .map(|v| v as u8);
    let art = text("albumart");
    let albumart = if art.is_empty() {
        String::new()
    } else {
        base.join(&art)
            .ok()
            .filter(|u| matches!(u.scheme(), "http" | "https"))
            .map(|u| u.to_string())
            .unwrap_or_default()
    };
    Ok(State {
        status: status.into(),
        title: text("title"),
        artist: text("artist"),
        album: text("album"),
        albumart,
        volume,
        disable_volume_control: value
            .get("disableVolumeControl")
            .and_then(Value::as_bool)
            .unwrap_or(false)
            || volume.is_none(),
        mute: value.get("mute").and_then(Value::as_bool).unwrap_or(false),
    })
}

async fn fetch(client: &Client, url: Url) -> Result<Vec<u8>, String> {
    let mut response = client
        .get(url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .error_for_status()
        .map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|e| e.to_string())? {
        if bytes.len() + chunk.len() > 1_048_576 {
            return Err("Response is too large".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

async fn read_state(client: &Client, base: &Url) -> Result<State, String> {
    let bytes = fetch(client, base.join("api/v1/getState").unwrap()).await?;
    state(
        serde_json::from_slice(&bytes).map_err(|e| format!("Invalid JSON: {e}"))?,
        base,
    )
}

fn command_url(base: &Url, request: &Request) -> Result<Url, String> {
    let cmd = match request.op.as_str() {
        "play" => "play",
        "pause" => "pause",
        "previous" => "prev",
        "next" => "next",
        "volume" if request.volume.is_some_and(|v| v <= 100) => "volume",
        _ => return Err("Invalid command or volume".into()),
    };
    let mut url = base.join("api/v1/commands/").unwrap();
    url.query_pairs_mut().append_pair("cmd", cmd);
    if cmd == "volume" {
        url.query_pairs_mut()
            .append_pair("volume", &request.volume.unwrap().to_string());
    }
    Ok(url)
}

async fn command(client: &Client, base: &Url, request: &Request) -> Result<(), String> {
    let bytes = fetch(client, command_url(base, request)?).await?;
    // Some Volumio versions acknowledge commands with an empty or text body.
    if let Ok(v) = serde_json::from_slice::<Value>(&bytes)
        && (v.get("error").is_some_and(|e| !e.is_null() && e != false)
            || v.get("success") == Some(&Value::Bool(false)))
    {
        return Err(format!("Command rejected: {v}"));
    }
    Ok(())
}

async fn emit(value: Value) -> std::io::Result<()> {
    let mut out = tokio::io::stdout();
    let mut bytes = serde_json::to_vec(&value)?;
    bytes.push(b'\n');
    out.write_all(&bytes).await?;
    out.flush().await
}

fn retry_delay(failures: u32) -> Duration {
    Duration::from_secs((2_u64.pow(failures.min(5))).min(30))
}

struct Completed {
    id: Option<u64>,
    result: Result<Option<State>, String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::builder()
        .timeout(Duration::from_secs(3))
        .connect_timeout(Duration::from_secs(2))
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()?;
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let mut base: Option<Url> = None;
    let mut queue: VecDeque<Request> = VecDeque::new();
    let mut job: Option<JoinHandle<Completed>> = None;
    let mut active_id = None;
    let mut online = false;
    let mut volume_enabled = false;
    let mut failures = 0;
    let mut next_poll = Instant::now();
    emit(json!({"type":"ready","protocol":1})).await?;
    loop {
        if job.is_none()
            && let Some(endpoint) = base.clone()
        {
            let http = client.clone();
            if let Some(request) = queue.pop_front() {
                active_id = Some(request.id);
                job = Some(tokio::spawn(async move {
                    Completed {
                        id: Some(request.id),
                        result: command(&http, &endpoint, &request).await.map(|()| None),
                    }
                }));
            } else if Instant::now() >= next_poll {
                active_id = None;
                job = Some(tokio::spawn(async move {
                    Completed {
                        id: None,
                        result: read_state(&http, &endpoint).await.map(Some),
                    }
                }));
            }
        }
        tokio::select! {
            line = lines.next_line() => {
                let Some(line) = line? else { break };
                let request = if line.len() <= 65536 { serde_json::from_str::<Request>(&line).ok() } else { None };
                let Some(request) = request else {
                    emit(json!({"type":"result","id":null,"ok":false,"error":"Invalid JSON request"})).await?;
                    continue;
                };
                if request.op == "configure" {
                    match address(request.address.as_deref().unwrap_or("")) {
                        Ok(url) => {
                            if let Some(task) = job.take() { task.abort(); }
                            if let Some(id) = active_id.take() {
                                emit(json!({"type":"result","id":id,"ok":false,"error":"Address changed; command outcome unknown"})).await?;
                            }
                            for old in queue.drain(..) {
                                emit(json!({"type":"result","id":old.id,"ok":false,"error":"Address changed"})).await?;
                            }
                            base = Some(url.clone()); online = false; volume_enabled = false; failures = 0; next_poll = Instant::now();
                            emit(json!({"type":"configured","id":request.id,"address":url.as_str()})).await?;
                            emit(json!({"type":"connection","online":false,"connecting":true})).await?;
                        }
                        Err(error) => emit(json!({"type":"result","id":request.id,"ok":false,"error":error})).await?,
                    }
                } else if request.op == "refresh" {
                    next_poll = Instant::now();
                    emit(json!({"type":"result","id":request.id,"ok":true})).await?;
                } else if !online || (request.op == "volume" && !volume_enabled) {
                    emit(json!({"type":"result","id":request.id,"ok":false,"error":"Player unreachable or control unavailable"})).await?;
                } else if let Err(error) = command_url(base.as_ref().unwrap(), &request) {
                    emit(json!({"type":"result","id":request.id,"ok":false,"error":error})).await?;
                } else if queue.len() >= 16 {
                    emit(json!({"type":"result","id":request.id,"ok":false,"error":"Too many pending commands"})).await?;
                } else { queue.push_back(request); }
            }
            finished = async { job.as_mut().unwrap().await }, if job.is_some() => {
                job = None; active_id = None;
                let completed = finished?;
                match completed.result {
                    Ok(Some(snapshot)) => {
                        online = true; volume_enabled = !snapshot.disable_volume_control; failures = 0;
                        next_poll = Instant::now() + POLL;
                        emit(json!({"type":"state","online":true,"state":snapshot})).await?;
                    }
                    Ok(None) => {
                        emit(json!({"type":"result","id":completed.id,"ok":true})).await?;
                        next_poll = Instant::now();
                    }
                    Err(error) => {
                        if let Some(id) = completed.id {
                            emit(json!({"type":"result","id":id,"ok":false,"error":error})).await?;
                        }
                        online = false; failures += 1;
                        let retry = retry_delay(failures);
                        next_poll = Instant::now() + retry;
                        emit(json!({"type":"connection","online":false,"connecting":false,"error":error,"retrySeconds":retry.as_secs()})).await?;
                        for old in queue.drain(..) {
                            emit(json!({"type":"result","id":old.id,"ok":false,"error":"Connection lost; command cancelled"})).await?;
                        }
                    }
                }
            }
            _ = tokio::time::sleep_until(next_poll), if job.is_none() && base.is_some() => {}
        }
    }
    if let Some(task) = job {
        task.abort();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn normalize_state_and_art() {
        let base = address("http://volumio.local").unwrap();
        let s = state(
            json!({"status":"pause","volume":"20","albumart":"/albumart?a=b%20c"}),
            &base,
        )
        .unwrap();
        assert_eq!(s.volume, Some(20));
        assert_eq!(s.albumart, "http://volumio.local/albumart?a=b%20c");
        assert_eq!(s.title, "");
        assert!(!s.disable_volume_control);
        assert!(
            state(json!({"status":"stop","volume":null}), &base)
                .unwrap()
                .disable_volume_control
        );
        assert!(state(json!({"status":"oops"}), &base).is_err());
    }
    #[test]
    fn rejects_bad_addresses_and_commands() {
        for raw in [
            "file:///tmp/x",
            "http://user:pass@host",
            "http://host/path",
            "http://host?x=1",
            "junk",
        ] {
            assert!(address(raw).is_err(), "{raw}");
        }
        let base = address("http://localhost:3000/").unwrap();
        let mut r = Request {
            id: 1,
            op: "volume".into(),
            volume: Some(101),
            address: None,
        };
        assert!(command_url(&base, &r).is_err());
        r.volume = Some(0);
        assert_eq!(
            command_url(&base, &r).unwrap().query(),
            Some("cmd=volume&volume=0")
        );
        r.op = "previous".into();
        assert_eq!(command_url(&base, &r).unwrap().query(), Some("cmd=prev"));
    }
    #[test]
    fn backoff_is_bounded() {
        assert_eq!(retry_delay(1).as_secs(), 2);
        assert_eq!(retry_delay(4).as_secs(), 16);
        assert_eq!(retry_delay(100).as_secs(), 30);
    }
}
