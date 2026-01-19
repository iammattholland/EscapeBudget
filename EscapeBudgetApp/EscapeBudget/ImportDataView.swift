import SwiftUI

struct ImportDataView: View {
    let initialAccount: Account?

    init(initialAccount: Account? = nil) {
        self.initialAccount = initialAccount
    }

    var body: some View {
        ImportDataViewImpl(initialAccount: initialAccount)
    }
}
