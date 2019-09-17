//
//  AppDelegate.swift
//  MuteSpotifyAds
//
//  Created by Simon Meusel on 25.05.18.
//  Copyright © 2019 Simon Meusel. All rights reserved.
//

import Cocoa
import Foundation

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    let endlessPrivateSessionKey = "EndlessPrivateSession"
    let restartToSkipAdsKey = "RestartToSkipAds"
    let startSpotifyKey = "StartSpotify"
    let notificationsKey = "Notifications"
    let songLogPathKey = "SongLogPath"
    let quitSpotify = "QuitSpotify"
    
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var titleMenuItem: NSMenuItem!
    @IBOutlet weak var endlessPrivateSessionCheckbox: NSMenuItem!
    @IBOutlet weak var restartToSkipAdsCheckbox: NSMenuItem!
    @IBOutlet weak var startSpotifyCheckbox: NSMenuItem!
    @IBOutlet weak var notificationsCheckbox: NSMenuItem!
    @IBOutlet weak var songLogCheckbox: NSMenuItem!
    
    var notificationsEnabled = false
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var spotifyManager: SpotifyManager?
    
    @IBAction func quit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    @IBAction func quitWithSotify(_ sender: Any) {
        spotifyManager?.closeSpotify()
    }
    
    @IBAction func openProjectWebsite(_ sender: Any) {
        openWebsite(url: "https://github.com/simonmeusel/MuteSpotifyAds")
    }
    
    @IBAction func openReportBugWebsite(_ sender: Any) {
        openWebsite(url: "https://github.com/simonmeusel/MuteSpotifyAds/issues")
    }
    
    @IBAction func openSimonMeuselWebsite(_ sender: Any) {
        openWebsite(url: "https://simonmeusel.de")
    }
    
    @IBAction func openLicenseWebsite(_ sender: Any) {
        openWebsite(url: "https://www.gnu.org/licenses/gpl-3.0.txt")
    }
    
    @IBAction func toggleEndlessPrivateSession(_ sender: NSMenuItem) {
        if spotifyManager!.endlessPrivateSessionEnabled {
            spotifyManager?.endlessPrivateSessionEnabled = false
            spotifyManager?.disablePrivateSession()
            sender.state = .off
        } else {
            spotifyManager?.endlessPrivateSessionEnabled = true
            spotifyManager?.enablePrivateSession()
            sender.state = .on
        }
        UserDefaults.standard.set(spotifyManager?.endlessPrivateSessionEnabled, forKey: endlessPrivateSessionKey)
    }
    @IBAction func toggleQuitSpotify(_ sender: NSMenuItem){
        if spotifyManager!.quitSpotify {
            spotifyManager?.quitSpotify = false
            sender.state = .off
        } else {
            spotifyManager?.quitSpotify = true
            sender.state = .on
        }
        UserDefaults.standard.set(spotifyManager?.restartToSkipAdsEnabled, forKey: quitSpotify)
    }
    
    @IBAction func toggleRestartToSkipAds(_ sender: NSMenuItem) {
        if spotifyManager!.restartToSkipAdsEnabled {
            spotifyManager?.restartToSkipAdsEnabled = false
            sender.state = .off
        } else {
            spotifyManager?.restartToSkipAdsEnabled = true
            sender.state = .on
        }
        UserDefaults.standard.set(spotifyManager?.restartToSkipAdsEnabled, forKey: restartToSkipAdsKey)
    }
    
    @IBAction func toggleNotifications(_ sender: NSMenuItem) {
        if notificationsEnabled {
            notificationsEnabled = false
            sender.state = .off
        } else {
            notificationsEnabled = true
            sender.state = .on
        }
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsKey)
    }
    
    @IBAction func toggleSpotifyStart(_ sender: NSMenuItem) {
        if spotifyManager!.startSpotify {
            spotifyManager?.startSpotify = false
            sender.state = .off
        } else {
            spotifyManager?.startSpotify = true
            sender.state = .on
        }
        UserDefaults.standard.set(spotifyManager?.startSpotify, forKey: startSpotifyKey)
    }
    
    @IBAction func toggleSongLog(_ sender: NSMenuItem) {
        if spotifyManager?.songLogPath != nil {
            spotifyManager?.songLogPath = nil
            sender.state = .off
        } else {
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["csv"]
            panel.allowsOtherFileTypes = true
            panel.canCreateDirectories = true
            panel.canSelectHiddenExtension = true
            panel.showsTagField = false
            panel.message = "The song log file will contain a entry for each song you listen.\nSelect where the .csv file should be saved on disk."
            panel.titleVisibility = .visible
            let result = panel.runModal()
            if result == .OK {
                spotifyManager?.songLogPath = panel.url?.path
                sender.state = .on
            } else {
                spotifyManager?.songLogPath = nil
            }
        }
        UserDefaults.standard.set(spotifyManager?.songLogPath, forKey: songLogPathKey)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSUserNotificationCenter.default.delegate = self
        
        setStatusBarTitle(title: .noAd)
        statusItem.menu = statusMenu
        
        // Get application version
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        titleMenuItem.title = titleMenuItem.title + " v\(version)"
        
        print("MuteSpotifyAds v\(version)")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
        
        spotifyManager = SpotifyManager(titleChangeHandler: {
            title in
            self.setStatusBarTitle(title: title)
        })
        
        if UserDefaults.standard.bool(forKey: endlessPrivateSessionKey) {
            spotifyManager?.enablePrivateSession()
            spotifyManager?.endlessPrivateSessionEnabled = true
            endlessPrivateSessionCheckbox.state = .on
        }
        
        if UserDefaults.standard.bool(forKey: restartToSkipAdsKey) {
            spotifyManager?.restartToSkipAdsEnabled = true
            restartToSkipAdsCheckbox.state = .on
        }
        
        if UserDefaults.standard.object(forKey: startSpotifyKey) == nil {
            UserDefaults.standard.set(true, forKey: startSpotifyKey)
        }
        if UserDefaults.standard.bool(forKey: startSpotifyKey) {
            spotifyManager?.startSpotify = true
            startSpotifyCheckbox.state = .on
        }
        
        if UserDefaults.standard.object(forKey: notificationsKey) == nil {
            UserDefaults.standard.set(true, forKey: notificationsKey)
        }
        if UserDefaults.standard.bool(forKey: notificationsKey) {
            notificationsEnabled = true
            notificationsCheckbox.state = .on
        }
        
        spotifyManager?.songLogPath = UserDefaults.standard.string(forKey: songLogPathKey)
        if spotifyManager?.songLogPath != nil {
            songLogCheckbox.state = .on
        }
        
        spotifyManager?.startWatchingForFileChanges()
    }
    
    func setStatusBarTitle(title: StatusBarTitle) {
        statusItem.title = title.rawValue
        
        if notificationsEnabled && title == StatusBarTitle.ad {
            sendNotificatoin(title: "Muting Spotify advertisement")
        }
    }
    
    func sendNotificatoin(title: String) {
        let notification = NSUserNotification()
        
        notification.hasActionButton = false
        notification.title = title
        notification.informativeText = "You can disable notifications in the status bar"
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    func openWebsite(url: String) {
        let url = URL(string: url)
        NSWorkspace.shared.open(url!)
    }
    
}

