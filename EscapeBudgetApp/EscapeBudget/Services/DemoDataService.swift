import Foundation
import SwiftData

final class DemoDataService {
    static func generateDemoData(modelContext: ModelContext) {
        // 1. Create Accounts
        let checking = Account(name: "Chequing", type: .chequing, balance: 3450.50, isDemoData: true)
        let savings = Account(name: "High Yield Savings", type: .savings, balance: 15000.00, isDemoData: true)
        let creditCard = Account(name: "Visa Signature", type: .creditCard, balance: -850.25, isDemoData: true)
        
        modelContext.insert(checking)
        modelContext.insert(savings)
        modelContext.insert(creditCard)

        // Give the savings account some history so the detail view isn't empty.
        let seedCalendar = Calendar.current
        let seedToday = Date()
        let seedDate = seedCalendar.date(byAdding: .month, value: -6, to: seedToday) ?? seedToday
        createTransfer(
            date: seedDate,
            amount: 15000,
            fromAccount: checking,
            toAccount: savings,
            context: modelContext,
            memo: "Initial deposit"
        )
        
        // 2. Create Categories
        // Income Group (System) - Fetch existing from DataSeeder
        let incomeDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == "Income" })
        let incomeGroup = (try? modelContext.fetch(incomeDescriptor).first) ?? CategoryGroup(name: "Income", order: -1, type: .income)
        if incomeGroup.modelContext == nil { modelContext.insert(incomeGroup) }
        
        // Fetch income categories directly from context
        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        var paycheck = allCategories.first(where: { $0.name == "Paycheck" && $0.group?.typeRawValue == "Income" })
        var bonus = allCategories.first(where: { $0.name == "Bonus" && $0.group?.typeRawValue == "Income" })
        var interest = allCategories.first(where: { $0.name == "Interest" && $0.group?.typeRawValue == "Income" })
        
        // Create if they don't exist
        if paycheck == nil {
            paycheck = Category(name: "Paycheck", assigned: 0, activity: 0, isDemoData: true)
            paycheck?.group = incomeGroup
            modelContext.insert(paycheck!)
        }
        if bonus == nil {
            bonus = Category(name: "Bonus", assigned: 0, activity: 0, isDemoData: true)
            bonus?.group = incomeGroup
            modelContext.insert(bonus!)
        }
        if interest == nil {
            interest = Category(name: "Interest", assigned: 0, activity: 0, isDemoData: true)
            interest?.group = incomeGroup
            modelContext.insert(interest!)
        }


        // Expense Groups - Using budget template categories
        // House
        let house = CategoryGroup(name: "House", order: 0, isDemoData: true)
        let mortgage = Category(name: "Mortgage", assigned: 1500, activity: 0, isDemoData: true)
        let homeInsurance = Category(name: "Home Insurance", assigned: 150, activity: 0, isDemoData: true)
        let propertyTaxes = Category(name: "Property Taxes", assigned: 300, activity: 0, isDemoData: true)
        house.categories = [mortgage, homeInsurance, propertyTaxes]

        // Bills & Utilities
        let billsUtilities = CategoryGroup(name: "Bills & Utilities", order: 1, isDemoData: true)
        let electricity = Category(name: "Electricity", assigned: 120, activity: 0, isDemoData: true)
        let gasUtility = Category(name: "Gas Utility", assigned: 80, activity: 0, isDemoData: true)
        let internet = Category(name: "Internet", assigned: 80, activity: 0, isDemoData: true)
        let cellphone = Category(name: "Cellphone", assigned: 70, activity: 0, isDemoData: true)
        billsUtilities.categories = [electricity, gasUtility, internet, cellphone]

        // Food & Dining
        let foodDining = CategoryGroup(name: "Food & Dining", order: 2, isDemoData: true)
        let groceries = Category(name: "Groceries & Essentials", assigned: 600, activity: 0, isDemoData: true)
        let restaurants = Category(name: "Restaurants", assigned: 250, activity: 0, isDemoData: true)
        let coffeeShops = Category(name: "Coffee Shops", assigned: 80, activity: 0, isDemoData: true)
        let alcoholBars = Category(name: "Alcohol & Bars", assigned: 100, activity: 0, isDemoData: true)
        foodDining.categories = [groceries, restaurants, coffeeShops, alcoholBars]

        // Auto & Transport
        let autoTransport = CategoryGroup(name: "Auto & Transport", order: 3, isDemoData: true)
        let autoInsurance = Category(name: "Auto Insurance", assigned: 145, activity: 0, isDemoData: true)
        let gas = Category(name: "Gas", assigned: 200, activity: 0, isDemoData: true)
        let publicTransport = Category(name: "Public Transportation", assigned: 100, activity: 0, isDemoData: true)
        let autoMaintenance = Category(name: "Auto Maintenance", assigned: 100, activity: 0, isDemoData: true)
        autoTransport.categories = [autoInsurance, gas, publicTransport, autoMaintenance]

        // Entertainment
        let entertainment = CategoryGroup(name: "Entertainment", order: 4, isDemoData: true)
        let subscriptions = Category(name: "Subscriptions", assigned: 50, activity: 0, isDemoData: true)
        let entertainmentGeneral = Category(name: "Entertainment", assigned: 150, activity: 0, isDemoData: true)
        let dateNight = Category(name: "Date Night", assigned: 100, activity: 0, isDemoData: true)
        entertainment.categories = [subscriptions, entertainmentGeneral, dateNight]

        // Health & Fitness
        let healthFitness = CategoryGroup(name: "Health & Fitness", order: 5, isDemoData: true)
        let gym = Category(name: "Gym Membership", assigned: 45, activity: 0, isDemoData: true)
        let healthServices = Category(name: "Health Services", assigned: 100, activity: 0, isDemoData: true)
        healthFitness.categories = [gym, healthServices]

        // Shopping
        let shopping = CategoryGroup(name: "Shopping", order: 6, isDemoData: true)
        let clothing = Category(name: "Clothing", assigned: 150, activity: 0, isDemoData: true)
        let electronics = Category(name: "Electronics", assigned: 100, activity: 0, isDemoData: true)
        let toiletries = Category(name: "Toiletries", assigned: 50, activity: 0, isDemoData: true)
        shopping.categories = [clothing, electronics, toiletries]

        // Personal Care
        let personalCare = CategoryGroup(name: "Personal Care", order: 7, isDemoData: true)
        let personalCareServices = Category(name: "Personal Care Services", assigned: 80, activity: 0, isDemoData: true)
        personalCare.categories = [personalCareServices]

        // Giving
        let giving = CategoryGroup(name: "Giving", order: 8, isDemoData: true)
        let charity = Category(name: "Charity", assigned: 200, activity: 0, isDemoData: true)
        let gifts = Category(name: "Gifts", assigned: 100, activity: 0, isDemoData: true)
        giving.categories = [charity, gifts]

        modelContext.insert(incomeGroup)
        modelContext.insert(house)
        modelContext.insert(billsUtilities)
        modelContext.insert(foodDining)
        modelContext.insert(autoTransport)
        modelContext.insert(entertainment)
        modelContext.insert(healthFitness)
        modelContext.insert(shopping)
        modelContext.insert(personalCare)
        modelContext.insert(giving)

        // 3. Create Tags (for demo)
        let tagIncome = TransactionTag(name: "Income", colorHex: "#34C759", order: 0, isDemoData: true)
        let tagSubscription = TransactionTag(name: "Subscription", colorHex: "#5856D6", order: 1, isDemoData: true)
        let tagCoffee = TransactionTag(name: "Coffee Run", colorHex: "#FF9500", order: 2, isDemoData: true)
        let tagTravel = TransactionTag(name: "Travel", colorHex: "#5AC8FA", order: 3, isDemoData: true)
        let tagFamily = TransactionTag(name: "Family", colorHex: "#FF2D55", order: 4, isDemoData: true)
        let tagNeedsReview = TransactionTag(name: "Needs Review", colorHex: "#FF3B30", order: 5, isDemoData: true)
        let tagBills = TransactionTag(name: "Bills", colorHex: "#007AFF", order: 6, isDemoData: true)

        modelContext.insert(tagIncome)
        modelContext.insert(tagSubscription)
        modelContext.insert(tagCoffee)
        modelContext.insert(tagTravel)
        modelContext.insert(tagFamily)
        modelContext.insert(tagNeedsReview)
        modelContext.insert(tagBills)
        
        // 4. Generate Transactions (Last 12 Months)
        let calendar = Calendar.current
        let today = Date()
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let startDate = calendar.date(byAdding: .month, value: -11, to: startOfCurrentMonth) ?? today
        
        // Helper to add days
        func dateDaysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today)!
        }
        
        // Recurring Transactions
        for i in 0..<12 { // 12 months back to cover 12 full months
            let monthOffset = i
            guard let monthDate = calendar.date(byAdding: .month, value: -monthOffset, to: today) else { continue }
            
	            // Salary (1st and 15th)
	            if let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "Employer Inc.", amount: 2500, account: checking, category: paycheck, context: modelContext, tags: [tagIncome])
	            }
	            if let date15 = calendar.date(bySetting: .day, value: 15, of: monthDate), date15 <= today {
	                _ = createTransaction(date: date15, payee: "Employer Inc.", amount: 2500, account: checking, category: paycheck, context: modelContext, tags: [tagIncome])
	            }
            
	            // Mortgage (1st)
	            if let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "Home Loan Services", amount: -1500, account: checking, category: mortgage, context: modelContext, tags: [tagBills])
	            }

	            // Property Taxes (1st, every 3 months)
	            if monthOffset % 3 == 0, let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "County Tax Collector", amount: -300, account: checking, category: propertyTaxes, context: modelContext, tags: [tagBills])
	            }

	            // Home Insurance (1st, every 6 months)
	            if monthOffset % 6 == 0, let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "State Farm", amount: -150, account: checking, category: homeInsurance, context: modelContext, tags: [tagBills])
	            }

	            // Electricity (15th)
	            if let date15 = calendar.date(bySetting: .day, value: 15, of: monthDate), date15 <= today {
	                let amount = Decimal(Double.random(in: 90...150))
	                _ = createTransaction(date: date15, payee: "Electric Co", amount: -amount, account: checking, category: electricity, context: modelContext, tags: [tagBills])
	            }

	            // Gas Utility (15th)
	            if let date15 = calendar.date(bySetting: .day, value: 15, of: monthDate), date15 <= today {
	                let amount = Decimal(Double.random(in: 60...100))
	                _ = createTransaction(date: date15, payee: "Gas Company", amount: -amount, account: checking, category: gasUtility, context: modelContext, tags: [tagBills])
	            }

	            // Internet (20th)
	            if let date20 = calendar.date(bySetting: .day, value: 20, of: monthDate), date20 <= today {
	                _ = createTransaction(date: date20, payee: "FiberNet", amount: -80, account: creditCard, category: internet, context: modelContext, tags: [tagBills])
	            }

	            // Cellphone (25th)
	            if let date25 = calendar.date(bySetting: .day, value: 25, of: monthDate), date25 <= today {
	                _ = createTransaction(date: date25, payee: "Verizon", amount: -70, account: creditCard, category: cellphone, context: modelContext, tags: [tagBills])
	            }

	            // Auto Insurance (1st)
	            if let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "Geico", amount: -145, account: creditCard, category: autoInsurance, context: modelContext, tags: [tagBills])
	            }

	            // Subscriptions (5th)
	            if let date5 = calendar.date(bySetting: .day, value: 5, of: monthDate), date5 <= today {
	                _ = createTransaction(date: date5, payee: "Netflix", amount: -15.99, account: creditCard, category: subscriptions, context: modelContext, tags: [tagSubscription])
	                _ = createTransaction(date: date5, payee: "Spotify", amount: -10.99, account: creditCard, category: subscriptions, context: modelContext, tags: [tagSubscription])
	                _ = createTransaction(date: date5, payee: "Amazon Prime", amount: -14.99, account: creditCard, category: subscriptions, context: modelContext, tags: [tagSubscription])
	            }

	            // Gym Membership (1st)
	            if let date1 = calendar.date(bySetting: .day, value: 1, of: monthDate), date1 <= today {
	                _ = createTransaction(date: date1, payee: "24 Hour Fitness", amount: -45, account: creditCard, category: gym, context: modelContext, tags: [tagBills])
	            }

	            // Charity (monthly on 10th)
	            if let date10 = calendar.date(bySetting: .day, value: 10, of: monthDate), date10 <= today {
	                _ = createTransaction(date: date10, payee: "Red Cross", amount: -100, account: checking, category: charity, context: modelContext)
	            }
	        }

        // Credit card payments (Transfers): Chequing -> Visa Signature (twice)
        for monthsBack in [1, 2] {
            guard let monthDate = calendar.date(byAdding: .month, value: -monthsBack, to: today) else { continue }
            guard let paymentDate = calendar.date(bySetting: .day, value: 25, of: monthDate), paymentDate <= today else { continue }
            let amount = Decimal(Double.random(in: 350...650))
            createTransfer(
                date: paymentDate,
                amount: amount,
                fromAccount: checking,
                toAccount: creditCard,
                context: modelContext,
                memo: "Credit card payment",
                status: .cleared,
                tags: [tagBills]
            )
        }
        
        // Random Daily Transactions (Last 12 months up to current date)
        let dailyRangeDays = max(0, calendar.dateComponents([.day], from: startDate, to: today).day ?? 365)
        for i in 0..<(dailyRangeDays + 1) {
            let date = dateDaysAgo(i)
            
	            // Coffee Shops (60% chance)
	            if Double.random(in: 0...1) < 0.6 {
	                let amount = Decimal(Double.random(in: 4...8))
	                _ = createTransaction(date: date, payee: "Starbucks", amount: -amount, account: creditCard, category: coffeeShops, context: modelContext, tags: [tagCoffee])
	            }

	            // Groceries (Every ~5 days)
	            if i % 5 == 0 {
	                let amount = Decimal(Double.random(in: 80...200))
	                _ = createTransaction(date: date, payee: ["Whole Foods", "Trader Joe's", "Safeway"].randomElement()!, amount: -amount, account: creditCard, category: groceries, context: modelContext, tags: [tagFamily])
	            }

	            // Restaurants (Every ~3 days)
	            if i % 3 == 0 {
	                let amount = Decimal(Double.random(in: 20...80))
	                let picked = ["Local Burger", "Pizza Place", "Sushi Spot", "Taco Truck"].randomElement()!
	                let tags = Double.random(in: 0...1) < 0.15 ? [tagTravel] : nil
	                _ = createTransaction(date: date, payee: picked, amount: -amount, account: creditCard, category: restaurants, context: modelContext, tags: tags)
	            }

	            // Gas (Every ~7 days)
	            if i % 7 == 0 {
	                let amount = Decimal(Double.random(in: 40...75))
	                let payee = ["Shell Station", "Chevron", "76 Gas"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: gas, context: modelContext)
	            }

	            // Public Transportation (Random 15% chance)
	            if Double.random(in: 0...1) < 0.15 {
	                let amount = Decimal(Double.random(in: 2.50...15))
	                let payee = ["Metro Card", "Uber", "Lyft"].randomElement()!
	                let tags = payee.contains("Uber") || payee.contains("Lyft") ? [tagTravel] : nil
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: publicTransport, context: modelContext, tags: tags)
	            }

	            // Alcohol & Bars (Random 10% chance)
	            if Double.random(in: 0...1) < 0.1 {
	                let amount = Decimal(Double.random(in: 15...60))
	                _ = createTransaction(date: date, payee: "Neighborhood Bar", amount: -amount, account: creditCard, category: alcoholBars, context: modelContext)
	            }

	            // Entertainment (Random 8% chance)
	            if Double.random(in: 0...1) < 0.08 {
	                let amount = Decimal(Double.random(in: 20...100))
	                let payee = ["Movie Theater", "Concert Tickets", "Museum"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: entertainmentGeneral, context: modelContext)
	            }

	            // Health Services (Random 5% chance)
	            if Double.random(in: 0...1) < 0.05 {
	                let amount = Decimal(Double.random(in: 30...150))
	                let payee = ["CVS Pharmacy", "Doctor Visit", "Dentist"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: healthServices, context: modelContext)
	            }

	            // Clothing (Random 5% chance)
	            if Double.random(in: 0...1) < 0.05 {
	                let amount = Decimal(Double.random(in: 30...200))
	                let payee = ["Gap", "Target", "H&M"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: clothing, context: modelContext)
	            }

	            // Personal Care Services (Random 3% chance)
	            if Double.random(in: 0...1) < 0.03 {
	                let amount = Decimal(Double.random(in: 30...100))
	                let payee = ["Hair Salon", "Spa Day", "Barber"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: personalCareServices, context: modelContext)
	            }

	            // Gifts (Random 3% chance)
	            if Double.random(in: 0...1) < 0.03 {
	                let amount = Decimal(Double.random(in: 20...150))
	                _ = createTransaction(date: date, payee: "Gift Shop", amount: -amount, account: creditCard, category: gifts, context: modelContext, tags: [tagFamily])
	            }

	            // Toiletries (Random 7% chance)
	            if Double.random(in: 0...1) < 0.07 {
	                let amount = Decimal(Double.random(in: 10...50))
	                let payee = ["CVS", "Walgreens", "Target"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: toiletries, context: modelContext)
	            }

	            // Auto Maintenance (Random 2% chance)
	            if Double.random(in: 0...1) < 0.02 {
	                let amount = Decimal(Double.random(in: 50...300))
	                let payee = ["Oil Change", "Tire Shop", "Auto Repair"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: autoMaintenance, context: modelContext)
	            }

	            // Date Night (Random 5% chance)
	            if Double.random(in: 0...1) < 0.05 {
	                let amount = Decimal(Double.random(in: 50...150))
	                _ = createTransaction(date: date, payee: "Fine Dining Restaurant", amount: -amount, account: creditCard, category: dateNight, context: modelContext)
	            }

	            // Electronics (Random 1% chance)
	            if Double.random(in: 0...1) < 0.01 {
	                let amount = Decimal(Double.random(in: 50...500))
	                let payee = ["Best Buy", "Apple Store", "Amazon"].randomElement()!
	                _ = createTransaction(date: date, payee: payee, amount: -amount, account: creditCard, category: electronics, context: modelContext)
	            }
	        }
        
        // Uncategorized sample transactions to highlight in UI
        let uncategorizedSamples: [(daysAgo: Int, payee: String, amount: Decimal, account: Account, memo: String)] = [
            (3, "Mystery Charge", Decimal(-42.75), creditCard, "Pending review"),
            (7, "Cash Withdrawal", Decimal(-120), checking, "Categorize me"),
            (12, "Reimbursement", Decimal(180), checking, "Needs category assignment")
        ]
	        for sample in uncategorizedSamples {
	            _ = createTransaction(
	                date: dateDaysAgo(sample.daysAgo),
	                payee: sample.payee,
	                amount: sample.amount,
	                account: sample.account,
	                category: nil,
	                context: modelContext,
	                memo: sample.memo,
	                tags: [tagNeedsReview]
	            )
	        }
        
        // Update Activity for current month only (simplified for demo)
        // In a real app, activity is calculated per month.
        // The BudgetView calculates it dynamically based on filtered transactions, so we don't strictly need to set 'activity' property on Category if the view computes it.
        // However, let's set it for the current month's view.
        // We'll skip manual activity update since the view computes it now.
        
        // 5. Create Savings Goals
        let emergencyFund = SavingsGoal(
            name: "Emergency Fund",
            targetAmount: 10000,
            currentAmount: 4500,
            targetDate: calendar.date(byAdding: .month, value: 12, to: today),
            colorHex: "FF9500",
            notes: "6 months of expenses",
            isDemoData: true
        )
        modelContext.insert(emergencyFund)
        
        let vacationGoal = SavingsGoal(
            name: "Europe Vacation",
            targetAmount: 5000,
            currentAmount: 1200,
            monthlyContribution: 400,
            colorHex: "5AC8FA",
           notes: "Trip to Italy and France",
            isDemoData: true
        )
        modelContext.insert(vacationGoal)
        
        let newCar = SavingsGoal(
            name: "New Car Down Payment",
            targetAmount: 8000,
            currentAmount: 2800,
            targetDate: calendar.date(byAdding: .month, value: 18, to: today),
            colorHex: "34C759",
            isDemoData: true
        )
        modelContext.insert(newCar)
        
        let weddingFund = SavingsGoal(
            name: "Wedding Fund",
            targetAmount: 15000,
            currentAmount: 8500,
            targetDate: calendar.date(byAdding: .month, value: 10, to: today),
            colorHex: "FF2D55",
            notes: "Save for the big day!",
            isDemoData: true
        )
        modelContext.insert(weddingFund)
        
        // 6. Create Purchase Plans
        let laptop = PurchasePlan(
            itemName: "MacBook Pro 16\"",
            expectedPrice: 2499,
            purchaseDate: calendar.date(byAdding: .month, value: 2, to: today),
            url: "https://www.apple.com/macbook-pro",
            category: "Electronics",
            priority: 4,
            notes: "For work - need M3 Max chip",
            isDemoData: true
        )
        modelContext.insert(laptop)
        
        let furniture = PurchasePlan(
            itemName: "Living Room Sofa",
            expectedPrice: 1200,
            purchaseDate: calendar.date(byAdding: .month, value: 1, to: today),
            category: "Home",
            priority: 3,
            notes: "Looking at West Elm options",
            isDemoData: true
        )
        modelContext.insert(furniture)
        
        let watch = PurchasePlan(
            itemName: "Apple Watch Ultra 2",
            expectedPrice: 799,
            category: "Electronics",
            priority: 2,
            notes: "Wait for potential sale",
            isDemoData: true
        )
        modelContext.insert(watch)
        
        let tires = PurchasePlan(
            itemName: "Winter Tires",
            expectedPrice: 600,
            purchaseDate: calendar.date(byAdding: .month, value: 1, to: today),
            category: "Auto",
            priority: 5,
            notes: "Need before snow season",
            isDemoData: true
        )
        modelContext.insert(tires)
        
        let suit = PurchasePlan(
            itemName: "Navy Blue Suit",
            expectedPrice: 450,
            category: "Clothing",
            priority: 3,
            isPurchased: true,
            actualPrice: 420,
            actualPurchaseDate: calendar.date(byAdding: .day, value: -15, to: today),
            isDemoData: true
        )
        modelContext.insert(suit)
        
        // 7. Create Recurring Purchases
        let rentRecurring = RecurringPurchase(
            name: "Rent",
            amount: 1500,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 5, to: today)!,
            category: "Housing",
            isDemoData: true
        )
        modelContext.insert(rentRecurring)
        
        let internetRecurring = RecurringPurchase(
            name: "Internet & Cable",
            amount: 89.99,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 10, to: today)!,
            category: "Bills",
            isDemoData: true
        )
        modelContext.insert(internetRecurring)
        
        let carInsuranceRecurring = RecurringPurchase(
            name: "Car Insurance",
            amount: 145,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 15, to: today)!,
            category: "Transportation",
            isDemoData: true
        )
        modelContext.insert(carInsuranceRecurring)
        
        let netflixRecurring = RecurringPurchase(
            name: "Netflix",
            amount: 15.99,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 8, to: today)!,
            category: "Entertainment",
            isDemoData: true
        )
        modelContext.insert(netflixRecurring)
        
        let gymRecurring = RecurringPurchase(
            name: "Gym Membership",
            amount: 45,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 1, to: today)!,
            category: "Health",
            isDemoData: true
        )
        modelContext.insert(gymRecurring)
        
        let phoneRecurring = RecurringPurchase(
            name: "Phone Plan",
            amount: 70,
            frequency: .monthly,
            nextDate: calendar.date(byAdding: .day, value: 20, to: today)!,
            category: "Bills",
            isDemoData: true
        )
        modelContext.insert(phoneRecurring)

        // Demo Receipts
        // Create a grocery receipt from 3 days ago
        let groceryDate = dateDaysAgo(3)
        let groceryTransaction = createTransaction(
            date: groceryDate,
            payee: "Whole Foods Market",
            amount: -87.43,
            account: creditCard,
            category: groceries,
            context: modelContext,
            memo: "Weekly grocery shopping",
            tags: [tagFamily]
        )

        let groceryReceipt = ReceiptImage(
            createdDate: groceryDate,
            extractedText: "WHOLE FOODS MARKET\n365 Main St\nTransaction Date: \(groceryDate.formatted(date: .abbreviated, time: .omitted))\n\nOrganic Bananas    $3.99\nAlmond Milk        $4.49\nSpinach (2x)      $7.98\nChicken Breast    $15.99\nBread             $5.99\nAvocados (3x)     $8.97\nGreek Yogurt      $6.99\nOlive Oil        $12.99\nApples (5x)       $7.49\nCheddar Cheese    $8.55\n\nSubtotal:        $83.43\nTax:              $4.00\nTOTAL:           $87.43\n\nThank you for shopping!",
            items: [
                ReceiptItem(name: "Organic Bananas", price: 3.99, quantity: 1),
                ReceiptItem(name: "Almond Milk", price: 4.49, quantity: 1),
                ReceiptItem(name: "Spinach", price: 3.99, quantity: 2),
                ReceiptItem(name: "Chicken Breast", price: 15.99, quantity: 1),
                ReceiptItem(name: "Bread", price: 5.99, quantity: 1),
                ReceiptItem(name: "Avocados", price: 2.99, quantity: 3),
                ReceiptItem(name: "Greek Yogurt", price: 6.99, quantity: 1),
                ReceiptItem(name: "Olive Oil", price: 12.99, quantity: 1),
                ReceiptItem(name: "Apples", price: 1.50, quantity: 5),
                ReceiptItem(name: "Cheddar Cheese", price: 8.55, quantity: 1)
            ],
            totalAmount: 87.43,
            merchant: "Whole Foods Market",
            receiptDate: groceryDate,
            isDemoData: true
        )
        groceryReceipt.transaction = groceryTransaction
        modelContext.insert(groceryReceipt)

        // Create a restaurant receipt from 5 days ago
        let restaurantDate = dateDaysAgo(5)
        let restaurantTransaction = createTransaction(
            date: restaurantDate,
            payee: "Local Burger",
            amount: -45.87,
            account: creditCard,
            category: restaurants,
            context: modelContext,
            memo: "Dinner with friends"
        )

        let restaurantReceipt = ReceiptImage(
            createdDate: restaurantDate,
            extractedText: "LOCAL BURGER\n123 Elm Street\nServer: Sarah\nTable: 14\nDate: \(restaurantDate.formatted(date: .abbreviated, time: .omitted))\n\nClassic Burger      $14.99\nBacon Cheeseburger  $16.99\nSweet Potato Fries   $6.99\nOnion Rings          $5.99\n\nSubtotal:          $44.96\nTax:                $3.60\nTip:                $9.00\nTOTAL:             $57.56\n\nThank you!",
            items: [
                ReceiptItem(name: "Classic Burger", price: 14.99, quantity: 1),
                ReceiptItem(name: "Bacon Cheeseburger", price: 16.99, quantity: 1),
                ReceiptItem(name: "Sweet Potato Fries", price: 6.99, quantity: 1),
                ReceiptItem(name: "Onion Rings", price: 5.99, quantity: 1)
            ],
            totalAmount: 45.87,
            merchant: "Local Burger",
            receiptDate: restaurantDate,
            isDemoData: true
        )
        restaurantReceipt.transaction = restaurantTransaction
        modelContext.insert(restaurantReceipt)

        // 8. Create Debt Accounts
        let chaseVisa = DebtAccount(
            name: "Chase Visa",
            currentBalance: 4850,
            originalBalance: 6500,
            interestRate: 0.2199,  // 21.99% APR
            minimumPayment: 145,
            extraPayment: 50,
            colorHex: "FF3B30",
            notes: "High interest - prioritize payoff",
            isDemoData: true
        )
        modelContext.insert(chaseVisa)

        let carLoan = DebtAccount(
            name: "Car Loan",
            currentBalance: 12500,
            originalBalance: 22000,
            interestRate: 0.0649,  // 6.49% APR
            minimumPayment: 385,
            colorHex: "007AFF",
            notes: "2022 Honda Accord",
            isDemoData: true
        )
        modelContext.insert(carLoan)

        let studentLoan = DebtAccount(
            name: "Student Loan",
            currentBalance: 18200,
            originalBalance: 35000,
            interestRate: 0.0525,  // 5.25% APR
            minimumPayment: 210,
            colorHex: "5856D6",
            notes: "Federal loan - income-driven repayment",
            isDemoData: true
        )
        modelContext.insert(studentLoan)
    }
    
	    @MainActor
	    @discardableResult
	    private static func createTransaction(date: Date, payee: String, amount: Decimal, account: Account, category: Category?, context: ModelContext, memo: String? = nil, status: TransactionStatus = .cleared, tags: [TransactionTag]? = nil) -> Transaction {
	        let tx = Transaction(date: date, payee: payee, amount: amount, memo: memo, status: status, account: account, category: category, tags: tags, isDemoData: true)
	        context.insert(tx)
	        return tx
	    }

    @MainActor
    private static func createTransfer(
        date: Date,
        amount: Decimal,
        fromAccount: Account,
        toAccount: Account,
        context: ModelContext,
        memo: String? = nil,
        status: TransactionStatus = .cleared,
        tags: [TransactionTag]? = nil
    ) {
        let id = UUID()
        let outflow = Transaction(
            date: date,
            payee: "Transfer",
            amount: -amount,
            memo: memo,
            status: status,
            kind: .transfer,
            transferID: id,
            account: fromAccount,
            category: nil,
            tags: tags,
            isDemoData: true
        )
        let inflow = Transaction(
            date: date,
            payee: "Transfer",
            amount: amount,
            memo: memo,
            status: status,
            kind: .transfer,
            transferID: id,
            account: toAccount,
            category: nil,
            tags: tags,
            isDemoData: true
        )

        context.insert(outflow)
        context.insert(inflow)
    }

    static func ensureDemoAccountHistory(modelContext: ModelContext) {
        let demoAccounts = (try? modelContext.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.isDemoData }))) ?? []
        guard !demoAccounts.isEmpty else { return }

        guard
            let checking = demoAccounts.first(where: { $0.name == "Chequing" }),
            let savings = demoAccounts.first(where: { $0.name == "High Yield Savings" })
        else { return }

        let demoTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.isDemoData }))) ?? []
        let savingsID = savings.persistentModelID
        let hasSavingsHistory = demoTransactions.contains { $0.account?.persistentModelID == savingsID }
        guard !hasSavingsHistory else { return }

        let calendar = Calendar.current
        let today = Date()
        let seedDate = calendar.date(byAdding: .month, value: -6, to: today) ?? today
        createTransfer(
            date: seedDate,
            amount: 15000,
            fromAccount: checking,
            toAccount: savings,
            context: modelContext,
            memo: "Initial deposit"
        )
    }
}
