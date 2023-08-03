//
//  BigButtonStyle.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 04..
//

import SwiftUI

/// A customizable big button style
public struct BigButtonStyle: ButtonStyle {
  var foregroundColor: Color
  var backgroundColor: Color
  var pressedColor: Color

    public func makeBody(configuration: Self.Configuration) -> some View {
    configuration.label
      .font(.headline)
      .padding(10)
      .foregroundColor(foregroundColor)
      .background(configuration.isPressed ? pressedColor : backgroundColor)
      .cornerRadius(8)
  }
}

extension View {
  func bigButton (
    foregroundColor: Color = .white,
    backgroundColor: Color = .gray,
    pressedColor: Color = .accentColor
  ) -> some View {
    self.buttonStyle(
      BigButtonStyle (
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        pressedColor: pressedColor
      )
    )
  }
}
