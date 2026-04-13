import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showAddTransaction = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tag(0)

                TransactionListView()
                    .tag(1)

                // 占位 - 中间的添加按钮
                Color.clear
                    .tag(2)

                StatisticsView()
                    .tag(3)

                ImportView()
                    .tag(4)
            }

            // 自定义底部导航栏
            customTabBar
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView()
        }
    }

    // MARK: - 自定义 TabBar
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", title: "首页", tag: 0)
            tabButton(icon: "list.bullet.rectangle", title: "明细", tag: 1)

            // 中间添加按钮
            Button(action: { showAddTransaction = true }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(hex: "4F46E5").opacity(0.4), radius: 8, y: 4)

                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -20)

            tabButton(icon: "chart.pie.fill", title: "统计", tag: 3)
            tabButton(icon: "bolt.horizontal.fill", title: "自动化", tag: 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(icon: String, title: String, tag: Int) -> some View {
        Button(action: { selectedTab = tag }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selectedTab == tag ? Color(hex: "4F46E5") : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}
