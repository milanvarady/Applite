//
//  sendNotification.swift
//  Applite
//
//  Created by Milán Várady on 2023. 04. 15..
//

import Foundation
import UserNotifications
import OSLog

enum NotificationReason {
    case success
    case failure
}

/// Sends a push notifcation
///
/// Only sends the notification if the user has enabled notifications for the specified reason in settings
///
/// - Parameters:
///   - title: Notification title
///   - body: Notification body
///   - reason: Reason why the notification was sent, task success or failure
///
/// - Returns: `Void`
func sendNotification(title: String, body: String = "", reason: NotificationReason) async {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "sendNotification")

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    guard (settings.authorizationStatus == .authorized) ||
            (settings.authorizationStatus == .provisional) else {

            // Ask for authorization
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Failed to request notification authorization. Error: \(error.localizedDescription)")
        }

        return
    }
        
    /// Return if notifications are desabled for selected reason
    if (!UserDefaults.standard.bool(forKey: "notificationSuccess") && reason == .success)
        || (!UserDefaults.standard.bool(forKey: "notificationFailure") && reason == .failure) {
        return
    }

    let content = UNMutableNotificationContent()

    content.title = title
    content.body = body
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

    do {
        try await UNUserNotificationCenter.current().add(request)
    } catch {
        logger.error("Failed to send notication. Error: \(error.localizedDescription)")
    }
}
