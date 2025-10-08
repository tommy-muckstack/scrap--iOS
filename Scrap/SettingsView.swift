import SwiftUI

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Settings content
                ScrollView {
                    VStack(spacing: 24) {
                        // Appearance Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Appearance")
                                    .font(GentleLightning.Typography.heading)
                                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                Spacer()
                            }

                            VStack(spacing: 1) {
                                // Dark Mode Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Dark Mode")
                                            .font(GentleLightning.Typography.body)
                                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                        Text("Change app appearance")
                                            .font(GentleLightning.Typography.caption)
                                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { themeManager.isDarkMode },
                                        set: { _ in themeManager.toggleDarkMode() }
                                    ))
                                    .tint(GentleLightning.Colors.accentNeutral)
                                }
                                .padding(16)
                                .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))

                                // Divider
                                Rectangle()
                                    .fill(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode).opacity(0.1))
                                    .frame(height: 1)

                                // Voice Create Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Voice Create")
                                            .font(GentleLightning.Typography.body)
                                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                        Text("Record new note by voice")
                                            .font(GentleLightning.Typography.caption)
                                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { themeManager.useVoiceInput },
                                        set: { _ in themeManager.toggleVoiceInput() }
                                    ))
                                    .tint(GentleLightning.Colors.accentNeutral)
                                }
                                .padding(16)
                                .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium))
                            .shadow(
                                color: GentleLightning.Colors.shadow(isDark: themeManager.isDarkMode),
                                radius: 8,
                                x: 0,
                                y: 2
                            )
                        }
                        
                        // App Info Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("About")
                                    .font(GentleLightning.Typography.heading)
                                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                Spacer()
                            }
                            
                            VStack(spacing: 12) {
                                // App Icon and Name
                                HStack {
                                    Image("AppLogo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 40, height: 40)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Scrap")
                                            .font(GentleLightning.Typography.titleEmphasis)
                                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                        
                                        Text("The world's simplest notepad")
                                            .font(GentleLightning.Typography.caption)
                                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    }
                                    
                                    Spacer()
                                }
                                
                                // Version Info
                                HStack {
                                    Text("Version")
                                        .font(GentleLightning.Typography.body)
                                        .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    
                                    Spacer()
                                    
                                    Text("1.0.0")
                                        .font(GentleLightning.Typography.body)
                                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                    .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                                    .shadow(
                                        color: GentleLightning.Colors.shadow(isDark: themeManager.isDarkMode),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )
                            )
                        }
                        
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                    .padding(.top, 20)
                }
            }
            .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
            .navigationTitle("My Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
    }
}

#Preview {
    SettingsView(themeManager: ThemeManager.shared)
}