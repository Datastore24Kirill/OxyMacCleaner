import SwiftUI

struct SectionIntro: View {
  let icon: String
  let title: String
  let subtitle: String
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon).font(.system(size: 28, weight: .medium)).foregroundStyle(.teal)
        .frame(width: 64, height: 64).background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.title2.bold())
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 20))
  }
}
