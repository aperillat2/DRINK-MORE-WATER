import XCTest
@testable import DRINK_MORE_WATER

final class WaterIntakeViewModelGoalMetFlagTests: XCTestCase {
    
    private let userDefaults = UserDefaults.standard
    private let goalMetFlagKey = "waterIntakeGoalMetDate"
    
    override func setUp() {
        super.setUp()
        clearGoalMetFlag()
    }
    
    override func tearDown() {
        clearGoalMetFlag()
        super.tearDown()
    }
    
    func test_markGoalMetToday_setsFlagForToday() {
        let vm = WaterIntakeViewModel()
        XCTAssertFalse(vm.isGoalMetToday)
        
        vm.markGoalMetToday()
        
        XCTAssertTrue(vm.isGoalMetToday)
        XCTAssertEqual(storedGoalMetFlagDate(), DateUtils.todayString())
    }
    
    func test_resetIfNeeded_onNewDay_clearsFlag() {
        let vm = WaterIntakeViewModel()
        
        // Simulate flag set for yesterday
        userDefaults.set(yesterdayString(), forKey: goalMetFlagKey)
        userDefaults.synchronize()
        
        XCTAssertFalse(vm.isGoalMetToday)
        
        vm.resetIfNeeded()
        
        XCTAssertFalse(vm.isGoalMetToday)
        XCTAssertNil(storedGoalMetFlagDate())
    }
    
    func test_resetIfNeeded_onSameDay_keepsFlag() {
        let vm = WaterIntakeViewModel()
        
        // Set flag for today
        userDefaults.set(DateUtils.todayString(), forKey: goalMetFlagKey)
        userDefaults.synchronize()
        
        XCTAssertTrue(vm.isGoalMetToday)
        
        vm.resetIfNeeded()
        
        XCTAssertTrue(vm.isGoalMetToday)
    }
    
    func test_clearGoalMetFlag_clearsFlagAndAllowsRescheduling() {
        let vm = WaterIntakeViewModel()
        
        vm.markGoalMetToday()
        XCTAssertTrue(vm.isGoalMetToday)
        
        vm.clearGoalMetFlag()
        
        XCTAssertFalse(vm.isGoalMetToday)
        XCTAssertNil(storedGoalMetFlagDate())
        
        // After clearing, resetIfNeeded should not set flag or block rescheduling
        vm.resetIfNeeded()
        XCTAssertFalse(vm.isGoalMetToday)
    }
    
    // MARK: - Helpers
    
    private func clearGoalMetFlag() {
        userDefaults.removeObject(forKey: goalMetFlagKey)
        userDefaults.synchronize()
    }
    
    private func storedGoalMetFlagDate() -> String? {
        return userDefaults.string(forKey: goalMetFlagKey)
    }
    
    private func yesterdayString() -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: yesterday)
    }
}
