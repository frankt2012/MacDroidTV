import AppIntents
import Foundation

/// A paired TV exposed to the widget configuration UI.
public struct TVDeviceEntity: AppEntity, Identifiable, Hashable, Sendable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV")
    public static var defaultQuery = TVDeviceQuery()

    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

public struct TVDeviceQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [TVDeviceEntity] {
        let state = SharedStore.shared.load()
        return identifiers.compactMap { identifier in
            guard let uuid = UUID(uuidString: identifier),
                  let device = state.devices.first(where: { $0.id == uuid })
            else { return nil }
            return TVDeviceEntity(id: identifier, name: device.name)
        }
    }

    public func suggestedEntities() async throws -> [TVDeviceEntity] {
        SharedStore.shared.load().devices.map {
            TVDeviceEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

/// Lets each widget choose which paired TV it controls.
public struct TVWidgetConfigurationIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "Choose a TV"
    public static var description = IntentDescription("Select which TV this widget controls.")

    @Parameter(title: "TV")
    public var device: TVDeviceEntity?

    public init() {}
}
