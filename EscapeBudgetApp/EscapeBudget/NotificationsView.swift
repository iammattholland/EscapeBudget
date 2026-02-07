import SwiftUI
import SwiftData

struct NotificationsView: View {
    var embedded: Bool = false
    private let topChrome: AnyView?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppNotification.date, order: .reverse) private var notifications: [AppNotification]
        @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    @State private var showingDeleteAllConfirmFromMenu = false
    @State private var showingDeleteAllConfirmFromBottom = false
    
    init(embedded: Bool = false, topChrome: (() -> AnyView)? = nil) {
        self.embedded = embedded
        self.topChrome = topChrome?()
    }

    var body: some View {
        Group {
            if embedded {
                notificationsList
            } else {
                NavigationStack {
                    notificationsList
                        .navigationTitle("Notifications")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    dismiss()
                                }
                                .fontWeight(.semibold)
                            }
                            
                            ToolbarItem(placement: .topBarLeading) {
                                if !notifications.isEmpty {
                                    Menu {
                                        Button {
                                            markAllAsRead()
                                        } label: {
                                            Label("Mark All as Read", systemImage: "checkmark.circle")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            showingDeleteAllConfirmFromMenu = true
                                        } label: {
                                            Label("Delete All", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").appEllipsisIcon()
                                    }
                                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                                    .confirmationDialog("Delete all notifications?", isPresented: $showingDeleteAllConfirmFromMenu, titleVisibility: .visible) {
                                        Button("Delete All", role: .destructive) {
                                            clearAllNotifications()
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("This will remove all notifications from your feed.")
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    private var notificationsList: some View {
        List {
            if topChrome != nil {
                AppChromeListRow(topChrome: topChrome, scrollID: "NotificationsView.scroll")
            }

            if notifications.isEmpty {
                VStack(spacing: AppDesign.Theme.Spacing.medium) {
                    Image(systemName: "bell.slash")
                        .appDisplayText(AppDesign.Theme.DisplaySize.xLarge, weight: .regular)
                        .foregroundStyle(.secondary)
                    Text("No Notifications")
                        .appSectionTitleText()
                    Text("You're all caught up!")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .appElevatedCardSurface()
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(
                        top: AppDesign.Theme.Spacing.medium,
                        leading: AppDesign.Theme.Spacing.medium,
                        bottom: AppDesign.Theme.Spacing.medium,
                        trailing: AppDesign.Theme.Spacing.medium
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(notifications) { notification in
                    NotificationRow(notification: notification)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteNotification(notification)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                toggleReadStatus(notification)
                            } label: {
                                Label(
                                    notification.isRead ? "Mark Unread" : "Mark Read",
                                    systemImage: notification.isRead ? "envelope" : "envelope.open"
                                )
                            }
                            .tint(AppDesign.Colors.tint(for: appColorMode))
                        }
                }
            }
        }
        .listStyle(.plain)
        .appListCompactSpacing()
        .coordinateSpace(name: "NotificationsView.scroll")
        .safeAreaInset(edge: .bottom) {
            if !notifications.isEmpty {
                HStack(spacing: AppDesign.Theme.Spacing.tight) {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmFromBottom = true
                    } label: {
                        Text("Delete All")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryCTA()
                    .confirmationDialog("Delete all notifications?", isPresented: $showingDeleteAllConfirmFromBottom, titleVisibility: .visible) {
                        Button("Delete All", role: .destructive) {
                            clearAllNotifications()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all notifications from your feed.")
                    }

                    Button {
                        markAllAsRead()
                    } label: {
                        Text("Mark All Read")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    .appPrimaryCTA()
                }
                .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                .padding(.top, AppDesign.Theme.Spacing.small)
                .padding(.bottom, AppDesign.Theme.Spacing.tight)
                .background(.ultraThinMaterial)
            }
        }
        .onDisappear {
            markAllAsRead()
        }
    }
    
    private func deleteNotification(_ notification: AppNotification) {
        withAnimation {
            modelContext.delete(notification)
            updateBadgeStatus()
        }
    }
    
    private func toggleReadStatus(_ notification: AppNotification) {
        withAnimation {
            notification.isRead.toggle()
            updateBadgeStatus()
        }
    }
    
    private func clearAllNotifications() {
        withAnimation {
            for notification in notifications {
                modelContext.delete(notification)
            }
            settings.hasNotifications = false
            modelContext.safeSave(context: "NotificationsView.clearAllNotifications", showErrorToUser: false)
        }
    }
    
    private func markAllAsRead() {
        withAnimation {
            for notification in notifications {
                notification.isRead = true
            }
            settings.hasNotifications = false
            modelContext.safeSave(context: "NotificationsView.markAllAsRead", showErrorToUser: false)
        }
    }
    
    private func updateBadgeStatus() {
        // Check if there are any unread notifications
        // Note: This query might not reflect immediate changes in the context if not saved, 
        // but for UI responsiveness we can check the in-memory objects
        let hasUnread = notifications.contains { !$0.isRead }
        settings.hasNotifications = hasUnread
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    
    var iconColor: Color {
        switch notification.type {
        case .info: return AppDesign.Colors.info(for: appColorMode)
        case .success: return AppDesign.Colors.success(for: appColorMode)
        case .warning: return AppDesign.Colors.warning(for: appColorMode)
        case .alert: return AppDesign.Colors.danger(for: appColorMode)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.medium) {
            Image(systemName: notification.type.icon)
                .appTitleText()
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                HStack {
                    Text(notification.title)
                        .appSectionTitleText()
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if !notification.isRead {
                        Circle()
                            .fill(AppDesign.Colors.tint(for: appColorMode))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(notification.message)
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(notification.date.formatted(.relative(presentation: .named)))
                    .appCaption2Text()
                    .foregroundStyle(.secondary)
                    .padding(.top, AppDesign.Theme.Spacing.hairline)
            }
        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
        .opacity(notification.isRead ? 0.6 : 1.0)
    }
}

#Preview {
    NotificationsView()
        .modelContainer(for: AppNotification.self, inMemory: true)
}
