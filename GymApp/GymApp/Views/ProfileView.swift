import SwiftUI

struct ProfileView: View {
    @State private var userName = "Gym User"
    @State private var userWeight = "180"
    @State private var userHeight = "5'10\""
    @State private var fitnessGoal = "Build Muscle"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Personal Information")) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(userName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Gym Enthusiast")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    TextField("Name", text: $userName)
                    TextField("Weight (lbs)", text: $userWeight)
                        .keyboardType(.numberPad)
                    TextField("Height", text: $userHeight)
                }
                
                Section(header: Text("Fitness Goals")) {
                    Picker("Goal", selection: $fitnessGoal) {
                        Text("Build Muscle").tag("Build Muscle")
                        Text("Lose Weight").tag("Lose Weight")
                        Text("Increase Strength").tag("Increase Strength")
                        Text("Improve Endurance").tag("Improve Endurance")
                        Text("General Fitness").tag("General Fitness")
                    }
                }
                
                Section(header: Text("Preferences")) {
                    NavigationLink(destination: Text("Units: Imperial")) {
                        HStack {
                            Label("Units", systemImage: "ruler")
                            Spacer()
                            Text("Imperial")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink(destination: Text("Theme: System")) {
                        HStack {
                            Label("Theme", systemImage: "paintbrush")
                            Spacer()
                            Text("System")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink(destination: Text("Notifications")) {
                        Label("Notifications", systemImage: "bell")
                    }
                }
                
                Section(header: Text("App Info")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {}) {
                        HStack {
                            Label("About", systemImage: "info.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
