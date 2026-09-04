#!/usr/bin/env python3
"""
Simple AeroMaps Demo Video Creator
Creates a .mov video using QuickTime Player for reliable recording
"""

import subprocess
import time
import signal
import sys
import os
from datetime import datetime

class SimpleVideoRecorder:
    def __init__(self):
        self.recording = False
        self.output_file = None
        
    def start_recording(self, output_file="AeroMaps_Simple_Demo.mov"):
        """Start recording using QuickTime Player"""
        self.output_file = output_file
        print(f"🎬 Starting simple video recording to {output_file}...")
        
        try:
            # Use QuickTime Player to start screen recording
            # This is more reliable than ffmpeg on macOS
            cmd = [
                "osascript", "-e",
                f'tell application "QuickTime Player" to new screen recording'
            ]
            
            print("Starting QuickTime Player screen recording...")
            subprocess.run(cmd, capture_output=True)
            
            # Give QuickTime time to start
            time.sleep(3)
            self.recording = True
            print("✅ Recording started! (Please manually stop recording when demo completes)")
            
        except Exception as e:
            print(f"❌ Failed to start recording: {e}")
            return False
            
        return True
    
    def run_simple_demo(self):
        """Run a simple demo sequence"""
        print("🚀 Running simple demo...")
        
        # Simple demo sequence
        demo_sequence = [
            ("Opening", [
                ("Wait for app to load", lambda: time.sleep(3), 3),
            ]),
            
            ("Tab Navigation", [
                ("Tap Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Flights tab", lambda: self.simulate_tap(200, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Library tab", lambda: self.simulate_tap(300, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Return to Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            ("Search Features", [
                ("Tap search bar", lambda: self.simulate_tap(200, 150), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Type KSFO", lambda: self.simulate_text("KSFO"), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Press Enter", lambda: self.simulate_text("\n"), 1),
                ("Wait for map animation", lambda: time.sleep(4), 4),
                ("Show airport details", lambda: time.sleep(2), 2),
            ]),
            
            ("Waypoint Creation", [
                ("Tap map for waypoint 1", lambda: self.simulate_tap(150, 300), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap map for waypoint 2", lambda: self.simulate_tap(250, 400), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap map for waypoint 3", lambda: self.simulate_tap(200, 500), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            ("Bottom Sheet Features", [
                ("Drag bottom sheet up", lambda: self.simulate_swipe(200, 700, 200, 500), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Route Advisor", lambda: self.simulate_tap(100, 650), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap W&B button", lambda: self.simulate_tap(200, 650), 1),
                ("Wait for Flight Planner", lambda: time.sleep(3), 3),
            ]),
            
            ("Layer Controls", [
                ("Tap Airspace layer", lambda: self.simulate_tap(100, 600), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap Weather layer", lambda: self.simulate_tap(200, 600), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap Terrain layer", lambda: self.simulate_tap(300, 600), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            ("Closing", [
                ("Return to Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Show final view", lambda: time.sleep(3), 3),
            ]),
        ]
        
        total_duration = 0
        for section_name, actions in demo_sequence:
            print(f"\n📱 {section_name}")
            for action_desc, action_func, duration in actions:
                print(f"  → {action_desc} ({duration}s)")
                if callable(action_func):
                    action_func()
                total_duration += duration
        
        print(f"\n⏱️ Total demo duration: {total_duration} seconds")
        print("\n🎬 Demo completed! Please manually stop the QuickTime recording.")
        return True
    
    def simulate_tap(self, x, y):
        """Simulate a tap at coordinates x, y"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 tap {x} {y}"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0
    
    def simulate_swipe(self, start_x, start_y, end_x, end_y, duration=0.5):
        """Simulate a swipe gesture"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 swipe {start_x} {start_y} {end_x} {end_y} {duration}"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0
    
    def simulate_text(self, text):
        """Simulate typing text"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 text '{text}'"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0

def setup_simulator():
    """Set up the iPhone simulator"""
    print("📱 Setting up iPhone simulator...")
    
    try:
        # Check if simulator is running
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted"],
            capture_output=True,
            text=True
        )
        
        if "iPhone 16 Pro" not in result.stdout:
            print("Starting iPhone 16 Pro simulator...")
            subprocess.run(["xcrun", "simctl", "boot", "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4"])
            time.sleep(5)
        else:
            print("✅ iPhone 16 Pro simulator already running")
        
        return True
    except Exception as e:
        print(f"❌ Error setting up simulator: {e}")
        return False

def launch_app():
    """Launch the AeroMaps app"""
    print("🚀 Launching AeroMaps...")
    
    try:
        # Launch the app
        result = subprocess.run([
            "xcrun", "simctl", "launch", 
            "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4", 
            "com.example.AeroMaps"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ AeroMaps launched successfully")
            time.sleep(3)  # Wait for app to load
            return True
        else:
            print(f"❌ Failed to launch app: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Error launching app: {e}")
        return False

def signal_handler(signum, frame):
    """Handle Ctrl+C gracefully"""
    print("\n🛑 Interrupted by user")
    sys.exit(0)

def main():
    recorder = SimpleVideoRecorder()
    
    # Set up signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    
    print("🎬 Simple AeroMaps Demo Video Creator")
    print("=" * 50)
    print("This will create a .mov video using QuickTime Player")
    print("=" * 50)
    
    # Set up simulator
    if not setup_simulator():
        print("❌ Failed to set up simulator")
        return
    
    # Launch app
    if not launch_app():
        print("❌ Failed to launch app")
        return
    
    # Start recording
    if not recorder.start_recording():
        print("❌ Failed to start recording")
        return
    
    # Wait for recording to stabilize
    print("⏳ Waiting for recording to stabilize...")
    time.sleep(3)
    
    # Run the demo
    print("🎬 Starting demo sequence...")
    demo_success = recorder.run_simple_demo()
    
    if demo_success:
        print("\n🎉 Demo completed successfully!")
        print("📁 Please save the QuickTime recording as a .mov file")
        print("🎬 The video showcases all major AeroMaps features")
        print("💡 You can now edit it in iMovie or Final Cut Pro!")
    else:
        print("\n⚠️ Demo completed with some issues")

if __name__ == "__main__":
    main()
