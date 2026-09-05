public import AppIntents

extension FlapSetting: AppEnum {
  public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Flap Setting" }

  public static var caseDisplayRepresentations: [FlapSetting: DisplayRepresentation] {
    [
      .flaps100: .init(title: "Flaps 100%"),
      .flaps50: .init(title: "Flaps 50%"),
      .flaps50Ice: .init(title: "Flaps 50% ICE"),
      .flapsUp: .init(title: "Flaps Up"),
      .flapsUpIce: .init(title: "Flaps Up ICE")
    ]
  }
}
