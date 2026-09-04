import SwiftUI

struct WeatherPanelView: View {
    @ObservedObject var mapState: MapState
    @ObservedObject var weatherService: WeatherService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                Picker("Weather Type", selection: $selectedTab) {
                    Text("Radar").tag(0)
                    Text("Forecast").tag(1)
                    Text("Winds").tag(2)
                    Text("METARs").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    RadarView()
                        .tag(0)
                    
                    ForecastView()
                        .tag(1)
                    
                    WindsView()
                        .tag(2)
                    
                    MetarsView(weatherService: weatherService)
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .background(Color.black)
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("Unit", selection: $mapState.tempUnit) {
                        Text("°C").tag(TemperatureUnit.celsius)
                        Text("°F").tag(TemperatureUnit.fahrenheit)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 90)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Radar View
struct RadarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current Radar
                WeatherCard(
                    title: "Current Radar",
                    icon: "cloud.rain.fill",
                    color: .blue
                ) {
                    VStack(spacing: 12) {
                        // Simulated radar image
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .green.opacity(0.3), .yellow.opacity(0.3), .red.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 200)
                            .overlay(
                                VStack {
                                    Text("Radar Image")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Live precipitation data")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            )
                        
                        HStack {
                            WeatherLegendItem(color: .blue, label: "Light")
                            WeatherLegendItem(color: .green, label: "Moderate")
                            WeatherLegendItem(color: .yellow, label: "Heavy")
                            WeatherLegendItem(color: .red, label: "Severe")
                        }
                    }
                }
                
                // Satellite
                WeatherCard(
                    title: "Satellite",
                    icon: "cloud.fill",
                    color: .cyan
                ) {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.gray.opacity(0.3), .white.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 150)
                            .overlay(
                                VStack {
                                    Text("Satellite Image")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Cloud cover analysis")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            )
                    }
                }
                
                // Lightning
                WeatherCard(
                    title: "Lightning",
                    icon: "bolt.fill",
                    color: .yellow
                ) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lightning Activity")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("No lightning detected")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "bolt.slash.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Forecast View
struct ForecastView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // TAF Forecast
                WeatherCard(
                    title: "TAF Forecast",
                    icon: "clock.fill",
                    color: .purple
                ) {
                    VStack(spacing: 12) {
                        ForEach(0..<3) { index in
                            ForecastRow(
                                time: "\(12 + index * 6):00",
                                condition: index == 0 ? "VFR" : index == 1 ? "MVFR" : "IFR",
                                wind: "240° @ \(20 + index * 5)kt",
                                visibility: index == 0 ? "10+ SM" : index == 1 ? "5 SM" : "2 SM",
                                ceiling: index == 0 ? "Unlimited" : index == 1 ? "3000 ft" : "800 ft"
                            )
                            
                            if index < 2 {
                                Divider()
                                    .background(Color.white.opacity(0.2))
                            }
                        }
                    }
                }
                
                // Surface Analysis
                WeatherCard(
                    title: "Surface Analysis",
                    icon: "map.fill",
                    color: .orange
                ) {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 150)
                            .overlay(
                                VStack {
                                    Text("Surface Analysis Chart")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Pressure systems and fronts")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            )
                    }
                }
                
                // Icing Forecast
                WeatherCard(
                    title: "Icing Forecast",
                    icon: "snowflake",
                    color: .cyan
                ) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Icing Probability")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Low to moderate icing possible")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Winds View
struct WindsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Winds Aloft
                WeatherCard(
                    title: "Winds Aloft",
                    icon: "wind",
                    color: .green
                ) {
                    VStack(spacing: 12) {
                        ForEach(0..<5) { index in
                            let altitude = 3000 + index * 3000
                            let windSpeed = 15 + index * 5
                            let windDirection = 240 + index * 10
                            
                            WindRow(
                                altitude: "\(altitude) ft",
                                direction: "\(windDirection)°",
                                speed: "\(windSpeed) kt",
                                temperature: "\(5 - index * 2)°C"
                            )
                            
                            if index < 4 {
                                Divider()
                                    .background(Color.white.opacity(0.2))
                            }
                        }
                    }
                }
                
                // Wind Shear
                WeatherCard(
                    title: "Wind Shear",
                    icon: "arrow.up.and.down",
                    color: .red
                ) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Wind Shear Alert")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Moderate wind shear below 2000 ft")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - METARs View
struct MetarsView: View {
    @ObservedObject var weatherService: WeatherService
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(["KSFO", "KSJC", "KRNO", "KSQL", "KOAK"], id: \.self) { airport in
                    MetarCard(airport: airport, weatherService: weatherService)
                }
            }
            .padding()
        }
    }
}

// MARK: - Supporting Views
struct WeatherCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            content
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct WeatherLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white)
        }
    }
}

struct ForecastRow: View {
    let time: String
    let condition: String
    let wind: String
    let visibility: String
    let ceiling: String
    
    var conditionColor: Color {
        switch condition {
        case "VFR": return .green
        case "MVFR": return .yellow
        case "IFR": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(wind)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(condition)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(conditionColor)
                
                Text(visibility)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Text(ceiling)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct WindRow: View {
    let altitude: String
    let direction: String
    let speed: String
    let temperature: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(altitude)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(temperature)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(direction) @ \(speed)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Wind")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct MetarCard: View {
    let airport: String
    @ObservedObject var weatherService: WeatherService
    
    var weather: WeatherData? {
        weatherService.currentWeather[airport]
    }
    
    var body: some View {
        WeatherCard(
            title: airport,
            icon: "airplane.circle.fill",
            color: .blue
        ) {
            VStack(spacing: 12) {
                if let weather = weather {
                    VStack(alignment: .leading, spacing: 8) {
                        if let metar = weather.metar {
                            Text(metar)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        HStack {
                            if let wind = weather.wind {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Wind")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(wind.direction)° @ \(wind.speed)kt")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Spacer()
                            
                            if let visibility = weather.visibility {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Visibility")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(String(format: "%.1f", visibility)) SM")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading METAR...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            // Create a dummy airport to fetch weather
            let dummyAirport = Airport(
                icao: airport,
                name: airport,
                city: "",
                state: "",
                coordinate: .init(latitude: 0, longitude: 0),
                elevation: 0,
                runways: [],
                frequencies: [],
                services: []
            )
            Task { await weatherService.fetchWeather(for: dummyAirport, using: weatherService.aviationWeather) }
        }
    }
}
