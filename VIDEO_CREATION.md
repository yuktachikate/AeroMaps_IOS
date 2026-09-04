# 🎬 Create AeroMaps Demo Video

## 🚀 Quick Video Creation (5 minutes)

### **Step 1: Start Screen Recording**
```bash
# Open QuickTime Player
open -a "QuickTime Player"

# Start recording:
# 1. File → New Screen Recording
# 2. Click the red record button
# 3. Select the iPhone Simulator window
# 4. Click "Start Recording"
```

### **Step 2: Run Auto Demo**
```bash
# Make sure the app is running
xcrun simctl launch BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps

# Run the auto demo script
python3 auto_demo.py
```

### **Step 3: Stop Recording**
- Press `Cmd + Shift + 5` to stop recording
- Save the video as `AeroMaps_Demo_Raw.mov`

### **Step 4: Edit in iMovie**
```bash
# Open iMovie
open -a "iMovie"

# Import your recording and edit:
# 1. File → Import Media → Select AeroMaps_Demo_Raw.mov
# 2. Drag to timeline
# 3. Add titles, transitions, and music
# 4. Export as "AeroMaps_Demo_Final.mp4"
```

---

## 🎯 What the Auto Demo Shows

### **8 Automated Steps:**

1. **Tab Navigation** - Shows Map, Flights, Library tabs
2. **Search "KSFO"** - Demonstrates airport search
3. **Add Waypoints** - Creates route with 3 waypoints
4. **Bottom Sheet** - Shows action buttons and W&B
5. **Layer Controls** - Toggles airspace, weather, terrain
6. **Clear Route** - Resets the route
7. **Search "San Jose"** - Shows multiple airport search
8. **Floating Buttons** - Demonstrates location and mode controls

### **Total Duration:** ~2-3 minutes

---

## 🎥 Video Enhancement Tips

### **Add to iMovie:**
- **Opening Title**: "AeroMaps - Developed for Pilot Yukta"
- **Background Music**: Aviation-themed royalty-free music
- **Feature Callouts**: Text overlays for each feature
- **Closing Credits**: "Ready for Takeoff"

### **Professional Touches:**
- Smooth transitions between sections
- Feature highlights with arrows/circles
- Professional aviation background music
- Captions for accessibility

---

## 📱 Demo Features Showcased

### **Core Functionality:**
- ✅ **Map-first interface** with Google Maps-style UI
- ✅ **Universal search** for airports and cities
- ✅ **Real-time weather** integration
- ✅ **Route planning** with waypoints
- ✅ **Layer controls** for customization
- ✅ **Flight planning** tools
- ✅ **Document library** organization

### **User Experience:**
- ✅ **Smooth animations** and transitions
- ✅ **Intuitive navigation** with tab bar
- ✅ **Dark theme** optimized for aviation
- ✅ **Professional interface** design

---

## 🛠️ Troubleshooting

### **If auto demo doesn't work:**
```bash
# Check if app is running
ps aux | grep -i aeromaps

# Restart app if needed
xcrun simctl terminate BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
xcrun simctl launch BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
```

### **If coordinates are off:**
- Adjust the x,y coordinates in `auto_demo.py`
- Test with single taps first
- Make sure simulator window is properly sized

### **If recording quality is poor:**
- Close other applications
- Use external microphone
- Record in smaller chunks if needed

---

## 🎬 Final Video Structure

### **Opening (0:00-0:10)**
- Title: "AeroMaps - Aviation Navigation App"
- Subtitle: "Developed for Pilot Yukta"

### **Auto Demo (0:10-3:00)**
- 8 automated steps showing all features
- Smooth transitions between sections

### **Closing (3:00-3:10)**
- "AeroMaps - Ready for Takeoff"
- Credits: "Developed for Pilot Yukta"

---

## 🚀 Ready to Create Your Video?

1. **Start recording** with QuickTime
2. **Run the auto demo**: `python3 auto_demo.py`
3. **Stop recording** and save
4. **Edit in iMovie** with titles and music
5. **Export** your professional demo video!

**Total time**: ~5 minutes to create a professional demo video showcasing all AeroMaps features! 🎉
