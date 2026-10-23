import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
    id: test
    name: "VolumioOscilloscope"
    Component {
        id: scopeComponent
        Plugin.Oscilloscope { width: 40; height: 18 }
    }

    function test_shapes_cycle() {
        var scope = scopeComponent.createObject(test);
        verify(scope !== null);
        compare(scope.shapeAt(0), "sine");
        compare(scope.shapeAt(1), "saw");
        compare(scope.shapeAt(2), "square");
        compare(scope.shapeAt(3), "triangle");
        compare(scope.shapeAt(4), "sine");
        var phase = scope.phase;
        var morph = scope.morphClock;
        scope.advance();
        verify(scope.phase > phase);
        verify(scope.morphClock > morph);
        scope.destroy();
    }

    function test_morph_schedule() {
        var scope = scopeComponent.createObject(test);
        verify(scope !== null);
        scope.holdSeconds = 1;
        scope.morphSeconds = 1;
        scope.morphClock = 0.5;
        compare(scope.shapeIndex, 0);
        compare(scope.shapeMix, 0);
        scope.morphClock = 1.5;
        compare(scope.shapeIndex, 0);
        verify(scope.shapeMix > 0 && scope.shapeMix < 1);
        scope.morphClock = 2.5;
        compare(scope.shapeIndex, 1);
        compare(scope.shapeMix, 0);
        scope.destroy();
    }
}
