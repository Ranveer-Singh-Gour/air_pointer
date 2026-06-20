/// A single MediaPipe hand landmark, normalised to [0, 1] in each axis.
final class HandLandmarkPoint {
  const HandLandmarkPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}
