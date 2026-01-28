import SwiftUI
import SwiftData

struct NotificationsView: View {
    var embedded: Bool = false
    private let topChrome: AnyView?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppNotification.date, order: .reverse) private var notifications: [AppNotification]
    @AppStorage("hasNotifications") private var hasNotifications = false
    @Environment(\.appColorMode) private var appColorMode
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
                                        Image(systemName: "ellipsis.circle")
                                            .imageScale(.large)
                                    }
                                    .foregroundStyle(AppColors.tint(for: appColorMode))
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
            if let topChrome {
                topChrome
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ScrollOffsetReader(coordinateSpace: "NotificationsView.scroll", id: "NotificationsView.scroll")
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if notifications.isEmpty {
                ContentUnavailableView(
                    "No Notifications",
                    systemImage: "bell.slash",
                    description: Text("You're all caught up!")
                )
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
                            .tint(AppColors.tint(for: appColorMode))
                        }
                }
            }
        }
        .listStyle(.plain)
        .appListCompactSpacing()
        .coordinateSpace(name: "NotificationsView.scroll")
        .safeAreaInset(edge: .bottom) {
            if !notifications.isEmpty {
                HStack(spacing: AppTheme.Spacing.tight) {
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
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.tight)
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
            hasNotifications = false
            modelContext.safeSave(context: "NotificationsView.clearAllNotifications", showErrorToUser: false)
        }
    }
    
    private func markAllAsRead() {
        withAnimation {
            for notification in notifications {
                notification.isRead = true
            }
            hasNotifications = false
            modelContext.safeSave(context: "NotificationsView.markAllAsRead", showErrorToUser: false)
        }
    }
    
    private func updateBadgeStatus() {
        // Check if there are any unread notifications
        // Note: This query might not reflect immediate changes in the context if not saved, 
        // but for UI responsiveness we can check the in-memory objects
        let hasUnread = notifications.contains { !$0.isRead }
        hasNotifications = hasUnread
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    @Environment(\.appColorMode) private var appColorMode
    
    var iconColor: Color {
        switch notification.type {
        case .info: return AppColors.info(for: appColorMode)
        case .success: return AppColors.success(for: appColorMode)
        case .warning: return AppColors.warning(for: appColorMode)
        case .alert: return AppColors.danger(for: appColorMode)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            Image(systemName: notification.type.icon)
                .appTitleText()
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                HStack {
                    Text(notification.title)
                        .appSectionTitleText()
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if !notification.isRead {
                        Circle()
                            .fill(AppColors.tint(for: appColorMode))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(notification.message)
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(notification.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, AppTheme.Spacing.hairline)
            }
        }
        .padding(.vertical, AppTheme.Spacing.micro)
        .opacity(notification.isRead ? 0.6 : 1.0)
    }
}

#Preview {
    NotificationsView()
        .modelContainer(for: AppNotification.self, inMemory: true)
}
