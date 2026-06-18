import Foundation
import Logging

let config = try BridgeConfig.load()
let profile = CompatibilityProfile.loadFromEnv()

var logger = Logger(label: "codex-afm-bridge")
logger.logLevel = config.logLevel
logger.info("Compatibility profile: \(profile.name)")

let afm = AFMRuntime()
let availability = afm.availability()
if availability.isAvailable {
    logger.info("Apple Foundation Models available (\(SupportedModels.canonical)).")
} else {
    if case .unavailable(let reason) = availability {
        logger.warning("Apple Foundation Models unavailable: \(reason.message)")
    }
    logger.warning("Bridge will start, but /v1/responses will return afm_unavailable until the model is ready.")
}

let store = ResponseStore()
let services = BridgeServices(
    afm: afm,
    store: store,
    config: config,
    profile: profile,
    logger: logger
)

let server = BridgeServer(services: services)
try await server.run()
