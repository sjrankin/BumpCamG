# BumpCamG

A Godot 4 port of the core of DeskBlockCam: a live camera feed or a still image drawn as a grid of lit 3D shapes.

## Run

Open the folder in Godot 4.7 and press Play, or:

    /Applications/Godot.app/Contents/MacOS/Godot --path .

Pick an input in the panel (camera, image, or demo pattern), or drop an image onto the window.

## How it works

1. `shaders/pixellate.gdshader` averages the source (camera or image) down to one pixel per grid cell in a tiny SubViewport.
2. `shaders/bumps.gdshader` runs on a single `MultiMesh` with one instance per cell. The vertex stage reads that cell's color, scales the shape and lifts it by the chosen channel (brightness, red, green, blue, saturation, hue, inverse brightness).

Everything stays on the GPU, so changing a setting or a frame costs no CPU work.

## Controls

- Drag: rotate. Command-drag, right or middle drag: move the image. Wheel, pinch: zoom. Trackpad scroll: pan.
- Double-click: reset the view. `H`: hide or show the panel.

## Shapes

Blocks, Spheres, Cones, Pyramids, Cylinders, Rings, Squares, Circles, Triangles, Diamonds, Hexagons, Stars. Flat shapes face the front. Add shapes in `scripts/shape_library.gd`.

## Not yet ported

Per-shape option dialogs, combined/character shapes, particles, video files, image metadata, histogram.

## Test options

    Godot --path . -- --image=PATH --shape=Stars --height=Hue --columns=96 --orbit=20,-15 --shot=out.png [--shot-ui]
