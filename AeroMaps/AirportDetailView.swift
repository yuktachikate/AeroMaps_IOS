import SwiftUI

struct AirportDetailView: View {
    let airport: Airport
    @EnvironmentObject private var aviationWeather: AviationWeatherService
    @ObservedObject var weatherService: WeatherService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    AirportHeader(airport: airport)
                    
                    // Weather Section
                    WeatherSection(airport: airport, weatherService: weatherService)
                    
                    // Runways Section
                    RunwaysSection(airport: airport)
                    
                    // Frequencies Section
                    FrequenciesSection(airport: airport)
                    
                    // Services Section
                    ServicesSection(airport: airport)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle(airport.icao)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add to Route") {
                        // Add to route action
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .task {
            await weatherService.fetchWeather(for: airport, using: aviationWeather)
        }
    }
}

// MARK: - Airport Header
struct AirportHeader: View {
    let airport: Airport
    
    var body: some View {
        VStack(spacing: 12) {
            // Airport Icon and Name
            VStack(spacing: 8) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text(airport.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("\(airport.city), \(airport.state)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Airport Info Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                InfoCard(
                    title: "Elevation",
                    value: "\(airport.elevation) ft",
                    icon: "mountain.2.fill",
                    color: .green
                )
                
                InfoCard(
                    title: "Runways",
                    value: "\(airport.runways.count)",
                    icon: "arrow.left.and.right",
                    color: .orange
                )
                
                InfoCard(
                    title: "Frequencies",
                    value: "\(airport.frequencies.count)",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .purple
                )
                
                InfoCard(
                    title: "Services",
                    value: "\(airport.services.count)",
                    icon: "wrench.and.screwdriver.fill",
                    color: .cyan
                )
            }
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

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Weather Section
struct WeatherSection: View {
    let airport: Airport
    @ObservedObject var weatherService: WeatherService
    
    var weather: WeatherData? {
        weatherService.currentWeather[airport.icao]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Weather", icon: "cloud.sun.fill", color: .blue)
            
            if let weather = weather {
                VStack(spacing: 12) {
                    // Current Conditions
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Conditions")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            if let temp = weather.temperature {
                                Text("\(Int(temp))°C")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        if let wind = weather.wind {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Wind")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("\(wind.direction)° @ \(wind.speed)kt")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                if let gust = wind.gust {
                                    Text("Gusts \(gust)kt")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    // METAR
                    if let metar = weather.metar {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("METAR")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text(metar)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    // TAF
                    if let taf = weather.taf {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TAF")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text(taf)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading weather...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
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

// MARK: - Runways Section
struct RunwaysSection: View {
    let airport: Airport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Runways", icon: "arrow.left.and.right", color: .orange)
            
            LazyVStack(spacing: 12) {
                ForEach(airport.runways) { runway in
                    RunwayCard(runway: runway)
                }
            }
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

struct RunwayCard: View {
    let runway: Runway
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(runway.designation)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(runway.surface)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(runway.length) × \(runway.width)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    if runway.lighted {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
                    Text(runway.lighted ? "Lighted" : "Unlighted")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Frequencies Section
struct FrequenciesSection: View {
    let airport: Airport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Frequencies", icon: "antenna.radiowaves.left.and.right", color: .purple)
            
            LazyVStack(spacing: 12) {
                ForEach(airport.frequencies) { frequency in
                    FrequencyCard(frequency: frequency)
                }
            }
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

struct FrequencyCard: View {
    let frequency: Frequency
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(frequency.type)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(frequency.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Text(frequency.frequency)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Services Section
struct ServicesSection: View {
    let airport: Airport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Services", icon: "wrench.and.screwdriver.fill", color: .cyan)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(airport.services, id: \.self) { service in
                    ServiceChip(service: service)
                }
            }
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

struct ServiceChip: View {
    let service: String
    
    var body: some View {
        HStack {
            Image(systemName: serviceIcon(for: service))
                .foregroundColor(.cyan)
            Text(service)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }
    
    private func serviceIcon(for service: String) -> String {
        switch service.lowercased() {
        case "fuel": return "fuelpump.fill"
        case "maintenance": return "wrench.and.screwdriver.fill"
        case "rental cars": return "car.fill"
        case "hotel shuttle": return "bus.fill"
        case "restaurant": return "fork.knife"
        case "flight school": return "graduationcap.fill"
        case "casino shuttle": return "dice.fill"
        case "bart": return "tram.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}
