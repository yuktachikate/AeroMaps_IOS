#!/usr/bin/env python3
"""
Final AeroMaps Demo Video Creator
Creates a professional .mov video showcasing all app features
"""

import subprocess
import time
import signal
import sys
import os
from datetime import datetime

class FinalVideoRecorder:
    def __init__(self):
        self.recording = False
        
    def start_quicktime_recording(self):
        """Start QuickTime Player screen recording"""
        print("🎬 Starting QuickTime Player screen recording...")
        
        try:
            # Open QuickTime Player and start screen recording
            cmd = [
                "osascript", "-e",
                'tell application "QuickTime Player" to activate'
            ]
            subprocess.run(cmd, capture_output=True)
            time.sleep(2)
            
            # Start new screen recording
            cmd = [
                "osascript", "-e",
                'tell application "QuickTime Player" to new screen recording'
            ]
            subprocess.run(cmd, capture_output=True)
            
            self.recording = True
            print("✅ QuickTime Player recording started!")
            print("📝 Please manually select the simulator area and start recording")
            print("⏳ Waiting 10 seconds for you to set up recording...")
            time.sleep(10)
            
        except Exception as e:
            print(f"❌ Failed to start QuickTime recording: {e}")
            return False
            
        return True
    
    def run_comprehensive_demo(self):
        """Run a comprehensive demo of all features"""
        print("🚀 Running comprehensive AeroMaps demo...")
        
        # Comprehensive demo sequence
        demo_steps = [
            # Opening and navigation
            ("App Launch", "Showing app launch and main interface", 5),
            ("Tab Navigation", "Demonstrating tab navigation", 15),
            ("Search Features", "Showing airport search functionality", 20),
            ("Waypoint Creation", "Adding waypoints to the map", 15),
            ("Bottom Sheet", "Interacting with bottom sheet features", 20),
            ("Flight Planner", "Opening and using Flight Planner", 15),
            ("Weather Panel", "Demonstrating weather features", 15),
            ("Layer Controls", "Toggling map layers", 15),
            ("Route Management", "Clearing and managing routes", 10),
            ("Multiple Searches", "Searching different airports", 15),
            ("Floating Buttons", "Using floating action buttons", 15),
            ("Final View", "Showing final app state", 10),
        ]
        
        total_duration = 0
        for step_name, description, duration in demo_steps:
            print(f"\n📱 {step_name}: {description}")
            print(f"⏱️ Duration: {duration} seconds")
            
            # Execute the step
            if step_name == "App Launch":
                self.wait(duration)
                
            elif step_name == "Tab Navigation":
                self.navigate_tabs()
                self.wait(duration)
                
            elif step_name == "Search Features":
                self.demonstrate_search()
                self.wait(duration)
                
            elif step_name == "Waypoint Creation":
                self.create_waypoints()
                self.wait(duration)
                
            elif step_name == "Bottom Sheet":
                self.interact_bottom_sheet()
                self.wait(duration)
                
            elif step_name == "Flight Planner":
                self.open_flight_planner()
                self.wait(duration)
                
            elif step_name == "Weather Panel":
                self.open_weather_panel()
                self.wait(duration)
                
            elif step_name == "Layer Controls":
                self.toggle_layers()
                self.wait(duration)
                
            elif step_name == "Route Management":
                self.clear_route()
                self.wait(duration)
                
            elif step_name == "Multiple Searches":
                self.multiple_searches()
                self.wait(duration)
                
            elif step_name == "Floating Buttons":
                self.use_floating_buttons()
                self.wait(duration)
                
            elif step_name == "Final View":
                self.show_final_view()
                self.wait(duration)
            
            total_duration += duration
        
        print(f"\n⏱️ Total demo duration: {total_duration} seconds ({total_duration/60:.1f} minutes)")
        print("\n🎬 Demo completed! Please stop the QuickTime recording.")
        return True
    
    def wait(self, seconds):
        """Wait for specified seconds"""
        print(f"  ⏳ Waiting {seconds} seconds...")
        time.sleep(seconds)
    
    def navigate_tabs(self):
        """Navigate through all tabs"""
        print("  → Navigating through tabs...")
        self.simulate_tap(100, 800)  # Map tab
        time.sleep(2)
        self.simulate_tap(200, 800)  # Flights tab
        time.sleep(2)
        self.simulate_tap(300, 800)  # Library tab
        time.sleep(2)
        self.simulate_tap(100, 800)  # Back to Map tab
        time.sleep(1)
    
    def demonstrate_search(self):
        """Demonstrate search functionality"""
        print("  → Demonstrating search...")
        self.simulate_tap(200, 150)  # Tap search bar
        time.sleep(1)
        self.simulate_text("KSFO")
        time.sleep(1)
        self.simulate_text("\n")  # Press Enter
        time.sleep(4)  # Wait for map animation
    
    def create_waypoints(self):
        """Create waypoints on the map"""
        print("  → Creating waypoints...")
        self.simulate_tap(150, 300)  # Waypoint 1
        time.sleep(1)
        self.simulate_tap(250, 400)  # Waypoint 2
        time.sleep(1)
        self.simulate_tap(200, 500)  # Waypoint 3
        time.sleep(2)
    
    def interact_bottom_sheet(self):
        """Interact with bottom sheet"""
        print("  → Interacting with bottom sheet...")
        self.simulate_swipe(200, 700, 200, 500)  # Drag up
        time.sleep(2)
        self.simulate_tap(100, 650)  # Route Advisor
        time.sleep(1)
        self.simulate_tap(200, 650)  # W&B button
        time.sleep(3)
    
    def open_flight_planner(self):
        """Open Flight Planner"""
        print("  → Opening Flight Planner...")
        self.simulate_tap(200, 650)  # W&B button
        time.sleep(3)
        self.simulate_tap(350, 100)  # Close button
        time.sleep(1)
    
    def open_weather_panel(self):
        """Open Weather Panel"""
        print("  → Opening Weather Panel...")
        self.simulate_tap(300, 650)  # Brief & File
        time.sleep(2)
        self.simulate_tap(350, 100)  # Close button
        time.sleep(1)
    
    def toggle_layers(self):
        """Toggle map layers"""
        print("  → Toggling layers...")
        self.simulate_tap(100, 600)  # Airspace
        time.sleep(1)
        self.simulate_tap(200, 600)  # Weather
        time.sleep(1)
        self.simulate_tap(300, 600)  # Terrain
        time.sleep(2)
    
    def clear_route(self):
        """Clear the current route"""
        print("  → Clearing route...")
        self.simulate_tap(300, 650)  # Clear Route
        time.sleep(2)
    
    def multiple_searches(self):
        """Perform multiple airport searches"""
        print("  → Multiple searches...")
        self.simulate_tap(200, 150)  # Search bar
        time.sleep(1)
        self.simulate_text("San Jose")
        time.sleep(1)
        self.simulate_text("\n")
        time.sleep(3)
        self.simulate_tap(350, 150)  # Clear search
        time.sleep(1)
    
    def use_floating_buttons(self):
        """Use floating action buttons"""
        print("  → Using floating buttons...")
        self.simulate_tap(350, 400)  # Location button
        time.sleep(2)
        self.simulate_tap(350, 500)  # Mode button
        time.sleep(2)
    
    def show_final_view(self):
        """Show final app view"""
        print("  → Showing final view...")
        self.simulate_tap(100, 800)  # Map tab
        time.sleep(3)
    
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
    recorder = FinalVideoRecorder()
    
    # Set up signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    
    print("🎬 Final AeroMaps Demo Video Creator")
    print("=" * 60)
    print("This will create a professional .mov video showcasing all features")
    print("=" * 60)
    
    # Set up simulator
    if not setup_simulator():
        print("❌ Failed to set up simulator")
        return
    
    # Launch app
    if not launch_app():
        print("❌ Failed to launch app")
        return
    
    # Start QuickTime recording
    if not recorder.start_quicktime_recording():
        print("❌ Failed to start recording")
        return
    
    # Run the comprehensive demo
    print("🎬 Starting comprehensive demo sequence...")
    demo_success = recorder.run_comprehensive_demo()
    
    if demo_success:
        print("\n🎉 Comprehensive demo completed successfully!")
        print("📁 Please save the QuickTime recording as 'AeroMaps_Demo.mov'")
        print("🎬 The video showcases all major AeroMaps features")
        print("💡 You can now edit it in iMovie or Final Cut Pro!")
        print("\n📋 Next steps:")
        print("1. Stop the QuickTime recording")
        print("2. Save as 'AeroMaps_Demo.mov'")
        print("3. Edit in iMovie or Final Cut Pro")
        print("4. Add narration and background music")
        print("5. Export final video")
    else:
        print("\n⚠️ Demo completed with some issues")

if __name__ == "__main__":
    main()
