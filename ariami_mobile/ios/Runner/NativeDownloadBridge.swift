import Flutter
import Foundation

final class NativeDownloadBridge: NSObject, URLSessionDownloadDelegate {
  static let shared = NativeDownloadBridge()

  private let channelName = "ariami/native_downloads"
  private let sessionIdentifier = "com.ariami.mobile.background-downloads"
  private let defaults = UserDefaults.standard
  private var channel: FlutterMethodChannel?
  private var backgroundCompletionHandler: (() -> Void)?
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  func register(messenger: FlutterBinaryMessenger) {
    if channel != nil { return }
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler(handle)
    channel = methodChannel
    _ = session
  }

  func handleEventsForBackgroundURLSession(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == sessionIdentifier else {
      completionHandler()
      return
    }
    backgroundCompletionHandler = completionHandler
    _ = session
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(true)
    case "startDownload":
      startDownload(call, result: result)
    case "queryDownload":
      queryDownload(call, result: result)
    case "cancelDownload":
      cancelDownload(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startDownload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let taskId = args["taskId"] as? String,
      let urlString = args["url"] as? String,
      let url = URL(string: urlString),
      let destinationPath = args["destinationPath"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "Missing taskId, url, or destinationPath", details: nil))
      return
    }

    let totalBytes = (args["totalBytes"] as? NSNumber)?.int64Value ?? 0
    let title = args["title"] as? String ?? "Downloading"
    let downloadTask = session.downloadTask(with: url)
    downloadTask.taskDescription = taskId

    defaults.set(destinationPath, forKey: destinationKey(taskId))
    defaults.set(title, forKey: titleKey(taskId))
    defaults.set("running", forKey: stateKey(taskId))
    defaults.set(Int64(0), forKey: bytesKey(taskId))
    defaults.set(totalBytes, forKey: totalKey(taskId))
    defaults.removeObject(forKey: errorKey(taskId))
    defaults.synchronize()

    downloadTask.resume()
    result([
      "backend": "ios_urlsession",
      "nativeTaskId": String(downloadTask.taskIdentifier)
    ])
  }

  private func queryDownload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let taskId = args["taskId"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "Missing taskId", details: nil))
      return
    }

    session.getAllTasks { tasks in
      let storedState = self.defaults.string(forKey: self.stateKey(taskId)) ?? "unavailable"
      let hasActiveTask = tasks.contains { $0.taskDescription == taskId }
      let state: String
      if storedState == "completed" || storedState == "failed" || storedState == "cancelled" {
        state = storedState
      } else if hasActiveTask {
        state = "running"
      } else {
        state = "unavailable"
      }

      result([
        "state": state,
        "bytesDownloaded": self.defaults.object(forKey: self.bytesKey(taskId)) as? Int64 ?? 0,
        "totalBytes": self.defaults.object(forKey: self.totalKey(taskId)) as? Int64 ?? 0,
        "errorMessage": self.defaults.string(forKey: self.errorKey(taskId)) as Any
      ])
    }
  }

  private func cancelDownload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let taskId = args["taskId"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "Missing taskId", details: nil))
      return
    }

    session.getAllTasks { tasks in
      for task in tasks where task.taskDescription == taskId {
        task.cancel()
      }
      self.defaults.set("cancelled", forKey: self.stateKey(taskId))
      result(nil)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let taskId = downloadTask.taskDescription else { return }
    defaults.set("running", forKey: stateKey(taskId))
    defaults.set(totalBytesWritten, forKey: bytesKey(taskId))
    if totalBytesExpectedToWrite > 0 {
      defaults.set(totalBytesExpectedToWrite, forKey: totalKey(taskId))
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard
      let taskId = downloadTask.taskDescription,
      let destinationPath = defaults.string(forKey: destinationKey(taskId))
    else { return }

    let destinationURL = URL(fileURLWithPath: destinationPath)
    do {
      try FileManager.default.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: location, to: destinationURL)
      let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
      let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
      defaults.set(size, forKey: bytesKey(taskId))
      defaults.set(size, forKey: totalKey(taskId))
      defaults.set("completed", forKey: stateKey(taskId))
      defaults.removeObject(forKey: errorKey(taskId))
    } catch {
      defaults.set("failed", forKey: stateKey(taskId))
      defaults.set(error.localizedDescription, forKey: errorKey(taskId))
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let taskId = task.taskDescription else { return }
    if let error = error as NSError? {
      if error.code == NSURLErrorCancelled {
        defaults.set("cancelled", forKey: stateKey(taskId))
      } else if defaults.string(forKey: stateKey(taskId)) != "completed" {
        defaults.set("failed", forKey: stateKey(taskId))
        defaults.set(error.localizedDescription, forKey: errorKey(taskId))
      }
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }

  private func destinationKey(_ taskId: String) -> String { "nativeDownload.destination.\(taskId)" }
  private func titleKey(_ taskId: String) -> String { "nativeDownload.title.\(taskId)" }
  private func stateKey(_ taskId: String) -> String { "nativeDownload.state.\(taskId)" }
  private func bytesKey(_ taskId: String) -> String { "nativeDownload.bytes.\(taskId)" }
  private func totalKey(_ taskId: String) -> String { "nativeDownload.total.\(taskId)" }
  private func errorKey(_ taskId: String) -> String { "nativeDownload.error.\(taskId)" }
}
