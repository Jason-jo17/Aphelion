# Screenshots

The images in the repository's README. Generated, not drawn:

```sh
make screenshots
```

`tools/capture_screens.gd` drives the real App through the real screens under a
virtual display and saves what it sees, so a screenshot that looks wrong is the
interface looking wrong — fix the interface, do not retouch the PNG.

The empty `.gdignore` beside them is deliberate: it tells Godot not to scan this
directory, so these stay ordinary files instead of becoming imported textures
that would be compiled into every exported build for no reason.
