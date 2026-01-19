import SwiftUI

struct MonthNavigationHeader: View {
    @Binding var selectedDate: Date
    var isCompact: Bool = false
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation {
                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.primary)
                    .padding(isCompact ? 6 : 8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(selectedDate, format: isCompact ? .dateTime.month(.abbreviated).year() : .dateTime.month(.wide).year())
                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.primary)
                    .padding(isCompact ? 6 : 8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
