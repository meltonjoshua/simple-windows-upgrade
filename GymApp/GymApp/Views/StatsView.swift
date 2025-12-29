import SwiftUI

struct StatsView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Cards
                    VStack(spacing: 16) {
                        StatCard(
                            title: "Total Workouts",
                            value: "\(workoutStore.totalWorkouts)",
                            icon: "dumbbell.fill",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Total Time",
                            value: formatTotalTime(workoutStore.totalDuration),
                            icon: "clock.fill",
                            color: .green
                        )
                        
                        StatCard(
                            title: "Total Volume",
                            value: String(format: "%.0f lbs", workoutStore.totalVolume),
                            icon: "flame.fill",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                    
                    // This Week
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This Week")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        let weekWorkouts = workoutStore.workoutsThisWeek()
                        
                        if weekWorkouts.isEmpty {
                            Text("No workouts this week")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(weekWorkouts) { workout in
                                WorkoutSummaryRow(workout: workout)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    
                    // This Month
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This Month")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        let monthWorkouts = workoutStore.workoutsThisMonth()
                        let monthCount = monthWorkouts.count
                        let monthDuration = monthWorkouts.reduce(0) { $0 + $1.duration }
                        
                        HStack(spacing: 20) {
                            MiniStatCard(
                                title: "Workouts",
                                value: "\(monthCount)",
                                color: .purple
                            )
                            
                            MiniStatCard(
                                title: "Hours",
                                value: String(format: "%.1f", monthDuration / 3600),
                                color: .pink
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Statistics")
        }
    }
    
    private func formatTotalTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = Int(seconds) / 60
            return "\(minutes)m"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.2))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct MiniStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct WorkoutSummaryRow: View {
    let workout: Workout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.headline)
                
                Text(workout.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(workout.formattedDuration)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        StatsView()
            .environmentObject(WorkoutStore())
    }
}
