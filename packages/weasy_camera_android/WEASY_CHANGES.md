# Weasy CameraX adapter

Vendored from the official Flutter camera_android_camerax 0.6.30 pub archive.
Upstream repository: https://github.com/flutter/packages/tree/main/packages/camera/camera_android_camerax
Original BSD license and source copyright notices are retained in LICENSE and source files.

Only runtime source is included. The Dart package, Android namespace and Pigeon
channel prefix are renamed to avoid collisions with camera's default implementation.
The app does not need a dependency_override. Weasy selects this implementation when
its capture controller is created; the public CameraController/CameraPreview API remains.
It is registered as an independent native plugin (no `implements: camera` metadata),
so Flutter does not exclude it when resolving camera's default implementation. Dart
selection is explicit in the Weasy controller, not global automatic registration.

RecorderProxyApi builds CameraX Recorder through WeasyRecorderFactory. A forwarding
Encoder copies PCM before submitting the original buffer. It delegates the original
buffer, PTS, EOS, cancellation and all encoder lifecycle calls unchanged. The copied
buffer goes to a bounded non-blocking STT queue. No second AudioRecord is created.

The factory uses package-private CameraX APIs, not reflection, and is deliberately
bound to CameraX **1.5.3**. Do not independently upgrade CameraX: compile and test this
adapter against the replacement before changing the pinned version. The adapter is
not a new video encoder and does not calculate or rewrite media timestamps.
