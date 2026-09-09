public import AppIntents

extension FlapSetting: AppEnum {
  public static var typeDisplayRepresentation: TypeDisplayRepresentation {
    .init(name: .init("Flap Setting", bundle: .sharedFramework))
  }

  public static var caseDisplayRepresentations: [FlapSetting: DisplayRepresentation] {
    [
      .flaps100: .init(title: .init("Flaps 100%", bundle: .sharedFramework)),
      .flaps50: .init(title: .init("Flaps 50%", bundle: .sharedFramework)),
      .flaps50Ice: .init(title: .init("Flaps 50% ICE", bundle: .sharedFramework)),
      .flapsUp: .init(title: .init("Flaps Up", bundle: .sharedFramework)),
      .flapsUpIce: .init(title: .init("Flaps Up ICE", bundle: .sharedFramework))
    ]
  }
}
