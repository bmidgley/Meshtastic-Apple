//
//  MeshtasticLogo.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI

struct MeshtasticLogo: View {
	
	@Environment(\.colorScheme) var colorScheme
	
	var body: some View {
		
		#if targetEnvironment(macCatalyst)
			VStack {
				Image("logo-white")
					.resizable()
					.renderingMode(.template)
					.foregroundColor(.accentColor)
					.scaledToFit()
			}
			.padding(.bottom, 5)
			.padding(.top, 5)
			.offset(x: -15)
		#else
			VStack {
				Image(colorScheme == .dark ? "logo-white" : "logo-black")
					.resizable()
					.renderingMode(.template)
					.scaledToFit()
			}
			.padding(.bottom, 5)
			.offset(x: -15)
		#endif
	}
}
