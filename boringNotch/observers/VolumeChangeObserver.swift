//
//  VolumeChangeObserver.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 24/03/25.
//

// Monitor volume changes. Send a notification every time we press the volume buttons

import CoreAudio
import AudioToolbox

class VolumeChangeObserver: ObservableObject{
    private var eventMonitor: Any?
        
    @Published var currentVolume: Float?
    @Published var isInternal: Bool = true
        
        init() {
            startMonitoring()
            currentVolume = getCurrentVolume()
        }
        
        private func startMonitoring(){
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                self?.handleEvent(event)
                return nil
            }
        }
    
    private func handleEvent(_ event: NSEvent) {
            if event.subtype.rawValue == 8 {
                let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
                
                if keyCode == NX_KEYTYPE_SOUND_UP || keyCode == NX_KEYTYPE_SOUND_DOWN || keyCode == NX_KEYTYPE_MUTE{
                    self.currentVolume = getCurrentVolume()
                    NotificationCenter.default.post(name: NSNotification.Name("ShowVolumeIndicator"), object: nil)
                }
                
            }
        }
    
    private func getCurrentVolume() -> Float?{
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )

        if deviceStatus != noErr {
            print("Error in retrieving audio output device")
            return nil
        }
        
        
        
        isInternal = isInternalSpeaker(deviceID: defaultOutputDeviceID)
        
        // Check if volume is mute
        var mute: UInt32 = 0
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            let muteStatus = AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &muteAddress,
                0,
                nil,
                &propertySize,
                &mute
            )

            if muteStatus != noErr {
                print("Unable to get mute status")
            }
        
        // Get device's volume
        var volume: Float = 0
        propertySize = UInt32(MemoryLayout<Float>.size)
        address = AudioObjectPropertyAddress(
            mSelector:kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let volumeStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &volume
        )

        if volumeStatus != noErr {
            print("Error in retrieving volume")
            return nil
        }

        if(mute == 1){
            return 0
        }
                
        return volume // value between 0.0 and 1.0
    }
    
    private func isInternalSpeaker(deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }
    
        
        deinit {
            if let eventMonitor = eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }
    
    
}
