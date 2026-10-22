use reqwest::{Client, Url};
use serde_json::{Value, json};
use std::collections::HashSet;
use tokio::sync::mpsc::Sender;

const PAGE_SIZE: usize = 100;
const MAX_ITEMS: usize = 10_000;

pub fn valid_album_uri(uri: &str) -> bool {
    uri.starts_with("albums://") && uri.len() > 9 && uri.len() <= 8192
}

fn internal_track(item: &Value) -> bool {
    let uri = item["uri"].as_str().unwrap_or_default();
    item["service"] == "mpd"
        && matches!(item["type"].as_str(), Some("song" | "track"))
        && uri.starts_with("music-library/INTERNAL/")
        && !uri.split('/').any(|part| matches!(part, "." | ".."))
}

struct Page {
    items: Vec<Value>,
    more: bool,
}

async fn page(client: &Client, base: &Url, uri: &str, offset: usize) -> Result<Page, String> {
    let mut url = base.join("api/v1/browse").unwrap();
    url.query_pairs_mut()
        .append_pair("uri", uri)
        .append_pair("limit", &PAGE_SIZE.to_string())
        .append_pair("offset", &offset.to_string());
    let bytes = super::fetch(client, url).await?;
    let value: Value =
        serde_json::from_slice(&bytes).map_err(|e| format!("Invalid library JSON: {e}"))?;
    let lists = value["navigation"]["lists"]
        .as_array()
        .ok_or("Invalid library response: missing lists")?;
    // Album and track listings are a single pageable list, unlike the source menu.
    if lists.len() != 1 {
        return Err("Unsupported library response: expected one album or track list".into());
    }
    let items = lists[0]["items"]
        .as_array()
        .ok_or("Invalid library response: missing items")?
        .clone();
    if offset + items.len() > MAX_ITEMS {
        return Err("Library listing exceeds the 10,000-item limit".into());
    }
    let more = if let Some(count) = lists[0]["count"].as_u64() {
        if count > MAX_ITEMS as u64 {
            return Err("Library listing exceeds the 10,000-item limit".into());
        }
        offset + items.len() < count as usize
    } else {
        items.len() >= PAGE_SIZE
    };
    if more && items.is_empty() {
        return Err("Library pagination returned an incomplete listing".into());
    }
    Ok(Page { items, more })
}

async fn tracks(
    client: &Client,
    base: &Url,
    uri: &str,
    first_only: bool,
) -> Result<Vec<Value>, String> {
    let mut offset = 0;
    let mut seen = HashSet::new();
    let mut internal = Vec::new();
    loop {
        let page = page(client, base, uri, offset).await?;
        offset += page.items.len();
        for item in page.items {
            let key = item["uri"].as_str().ok_or("Library item has no URI")?;
            if !seen.insert(key.to_owned()) {
                return Err(
                    "Library changed or pagination repeated a track; refresh and retry".into(),
                );
            }
            if internal_track(&item) {
                internal.push(item);
                if first_only {
                    return Ok(internal);
                }
            }
        }
        if !page.more {
            return Ok(internal);
        }
    }
}

pub async fn browse(client: Client, base: Url, id: u64, events: Sender<(u64, Value)>) {
    let result = scan(&client, &base, id, &events).await;
    let event = match result {
        Ok(()) => json!({"type":"albums", "id":id, "items":[], "done":true}),
        Err(error) => json!({"type":"library_error", "id":id, "error":error}),
    };
    let _ = events.send((id, event)).await;
}

async fn scan(
    client: &Client,
    base: &Url,
    id: u64,
    events: &Sender<(u64, Value)>,
) -> Result<(), String> {
    let mut offset = 0;
    let mut seen = HashSet::new();
    loop {
        let page = page(client, base, "albums://", offset).await?;
        offset += page.items.len();
        for item in page.items {
            let uri = item["uri"].as_str().ok_or("Album has no URI")?;
            if !valid_album_uri(uri) || item["service"] != "mpd" {
                continue;
            }
            if !seen.insert(uri.to_owned()) {
                return Err(
                    "Library changed or pagination repeated an album; refresh and retry".into(),
                );
            }
            if tracks(client, base, uri, true).await?.is_empty() {
                continue;
            }
            let art = item["albumart"].as_str().unwrap_or_default();
            let art = if art.is_empty() {
                None
            } else {
                base.join(art).ok()
            }
            .filter(|url| matches!(url.scheme(), "http" | "https"))
            .map(|url| url.to_string())
            .unwrap_or_default();
            events.send((id, json!({"type":"albums", "id":id, "done":false, "items":[{
                "uri":uri, "title":item["title"].as_str().unwrap_or("Untitled album"), "albumart":art
            }]}))).await.map_err(|_| "Library request cancelled")?;
        }
        if !page.more {
            return Ok(());
        }
    }
}

pub async fn play_album(client: &Client, base: &Url, uri: &str) -> Result<(), String> {
    // Resolve every page before making the single queue-changing request.
    let tracks = tracks(client, base, uri, false).await?;
    if tracks.is_empty() {
        return Err("This album contains no playable internal-storage tracks".into());
    }
    let body = serde_json::to_vec(&json!({"item":tracks[0], "list":tracks, "index":0}))
        .map_err(|e| e.to_string())?;
    if body.len() > 8 * 1_048_576 {
        return Err("Album queue payload exceeds 8 MiB; playback was not changed".into());
    }
    // A timeout after sending can mean Volumio applied the request. Never retry.
    let outcome = async {
        let response = client
            .post(base.join("api/v1/replaceAndPlay").unwrap())
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?;
        let bytes = super::response_bytes(response).await?;
        super::command_ack(&bytes)
    }
    .await;
    outcome.map_err(|error| format!("Album activation failed; queue/playback may have changed. Check the player before retrying. {error}"))
}
