//
//  AppDelegate.swift
//  MuteSpotifyAds
//
//  Created by Simon Meusel on 25.05.18.
//  Copyright © 2018 Simon Meusel. All rights reserved.
//

import Cocoa
import Foundation

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let endlessPrivateSessionKey = "EndlessPrivateSession"
    
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var titleMenuItem: NSMenuItem!
    @IBOutlet weak var endlessPrivateSessionCheckbox: NSMenuItem!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var spotifyManager: SpotifyManager?;
    
    @IBAction func quit(_ sender: Any) {
        NSApplication.shared.terminate(self)
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
            UserDefaults.standard.set(false, forKey: endlessPrivateSessionKey)
            spotifyManager?.disablePrivateSession()
            sender.state = .off
        } else {
            spotifyManager?.endlessPrivateSessionEnabled = true
            UserDefaults.standard.set(true, forKey: endlessPrivateSessionKey)
            spotifyManager?.enablePrivateSession()
            sender.state = .on
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setStatusBarTitle(title: .noAd)
        statusItem.menu = statusMenu
        
        // Get application version
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        titleMenuItem.title = titleMenuItem.title + " v\(version)"
        
        spotifyManager = SpotifyManager(titleChangeHandler: {
            title in
            self.setStatusBarTitle(title: title)
        })
        spotifyManager?.startWatchingForFileChanges()
        
        if UserDefaults.standard.bool(forKey: endlessPrivateSessionKey) {
            spotifyManager?.enablePrivateSession()
            spotifyManager?.endlessPrivateSessionEnabled = true
            endlessPrivateSessionCheckbox.state = .on
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func setStatusBarTitle(title: StatusBarTitle) {
        statusItem.title = title.rawValue
    }
    
    func openWebsite(url: String) {
        let url = URL(string: url)
        NSWorkspace.shared.open(url!)
    }
    
}

