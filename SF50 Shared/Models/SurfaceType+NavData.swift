import NavData

extension SurfaceType {
  /// The performance models' surface type for a surface NavData decoded.
  init(_ surface: NavData.SurfaceType) {
    switch surface {
      case .paved: self = .paved
      case .grooved: self = .grooved
      case .pfc: self = .pfc
      case .turf: self = .turf
    }
  }
}
