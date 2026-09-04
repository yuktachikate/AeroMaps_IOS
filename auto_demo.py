#!/usr/bin/env python3
"""
AeroMaps Auto Demo Script
Automatically demonstrates app features by simulating user interactions
"""

import time
import subprocess
import sys

def run_command(cmd):
    """Run a command and return the result"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0
    except Exception as e:
        print(f"Error running command: {e}")
        return False

def simulate_tap(x, y):
    """Simulate a tap at coordinates x, y"""
    cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 tap {x} {y}"
    return run_command(cmd)

def simulate_swipe(start_x, start_y, end_x, end_y, duration=0.5):
    """Simulate a swipe gesture"""
    cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 swipe {start_x} {start_y} {end_x} {end_y} {duration}"
    return run_command(cmd)

def simulate_text(text):
    """Simulate typing text"""
    cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 text '{text}'"
    return run_command(cmd)

def wait(seconds):
    """Wait for specified seconds"""
    print(f"Waiting {seconds} seconds...")
    time.sleep(seconds)

def print_step(step, description):
    """Print current step with description"""
    print(f"\n{'='*50}")
    print(f"STEP {step}: {description}")
    print(f"{'='*50}")

def main():
    print("🎬 AeroMaps Auto Demo Script")
    print("This script will automatically demonstrate app features")
    print("Make sure the app is running and visible on screen")
    print("Press Enter to start the demo...")
    input()
    
    # Demo steps with timing
    demo_steps = [
        # Step 1: Show tab navigation
        (1, "Showing Tab Navigation", [
            ("Tap Map tab", lambda: simulate_tap(100, 800)),
            ("Wait", lambda: wait(2)),
            ("Tap Flights tab", lambda: simulate_tap(200, 800)),
            ("Wait", lambda: wait(2)),
            ("Tap Library tab", lambda: simulate_tap(300, 800)),
            ("Wait", lambda: wait(2)),
            ("Return to Map tab", lambda: simulate_tap(100, 800)),
            ("Wait", lambda: wait(1)),
        ]),
        
        # Step 2: Search functionality
        (2, "Demonstrating Search", [
            ("Tap search bar", lambda: simulate_tap(200, 150)),
            ("Wait", lambda: wait(1)),
            ("Type KSFO", lambda: simulate_text("KSFO")),
            ("Wait", lambda: wait(1)),
            ("Press Enter", lambda: simulate_text("\n")),
            ("Wait", lambda: wait(3)),
            ("Clear search", lambda: simulate_tap(350, 150)),
            ("Wait", lambda: wait(1)),
        ]),
        
        # Step 3: Add waypoints
        (3, "Adding Waypoints", [
            ("Tap map to add waypoint 1", lambda: simulate_tap(150, 300)),
            ("Wait", lambda: wait(1)),
            ("Tap map to add waypoint 2", lambda: simulate_tap(250, 400)),
            ("Wait", lambda: wait(1)),
            ("Tap map to add waypoint 3", lambda: simulate_tap(200, 500)),
            ("Wait", lambda: wait(2)),
        ]),
        
        # Step 4: Bottom sheet interaction
        (4, "Bottom Sheet Features", [
            ("Drag bottom sheet up", lambda: simulate_swipe(200, 700, 200, 500)),
            ("Wait", lambda: wait(2)),
            ("Tap Route Advisor", lambda: simulate_tap(100, 650)),
            ("Wait", lambda: wait(1)),
            ("Tap W&B button", lambda: simulate_tap(200, 650)),
            ("Wait", lambda: wait(3)),
            ("Close Flight Planner", lambda: simulate_tap(350, 100)),
            ("Wait", lambda: wait(1)),
        ]),
        
        # Step 5: Layer controls
        (5, "Layer Controls", [
            ("Tap Airspace layer", lambda: simulate_tap(100, 600)),
            ("Wait", lambda: wait(1)),
            ("Tap Weather layer", lambda: simulate_tap(200, 600)),
            ("Wait", lambda: wait(1)),
            ("Tap Terrain layer", lambda: simulate_tap(300, 600)),
            ("Wait", lambda: wait(2)),
        ]),
        
        # Step 6: Clear route
        (6, "Clearing Route", [
            ("Tap Clear Route", lambda: simulate_tap(300, 650)),
            ("Wait", lambda: wait(2)),
        ]),
        
        # Step 7: Search different airports
        (7, "Multiple Airport Search", [
            ("Tap search bar", lambda: simulate_tap(200, 150)),
            ("Wait", lambda: wait(1)),
            ("Type San Jose", lambda: simulate_text("San Jose")),
            ("Wait", lambda: wait(1)),
            ("Press Enter", lambda: simulate_text("\n")),
            ("Wait", lambda: wait(3)),
            ("Clear search", lambda: simulate_tap(350, 150)),
            ("Wait", lambda: wait(1)),
        ]),
        
        # Step 8: Floating action buttons
        (8, "Floating Action Buttons", [
            ("Tap location button", lambda: simulate_tap(350, 400)),
            ("Wait", lambda: wait(2)),
            ("Tap mode button", lambda: simulate_tap(350, 500)),
            ("Wait", lambda: wait(2)),
        ]),
    ]
    
    # Execute demo steps
    for step_num, step_desc, actions in demo_steps:
        print_step(step_num, step_desc)
        
        for action_desc, action_func in actions:
            print(f"  → {action_desc}")
            success = action_func()
            if not success:
                print(f"    ⚠️  Action failed: {action_desc}")
    
    print("\n🎉 Demo completed!")
    print("The app has demonstrated all major features automatically.")
    print("You can now record this demo or run it again.")

if __name__ == "__main__":
    main()
