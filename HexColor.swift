//
//  HexColor.swift
//  ImagePalette
//
//  Original created by Google/Android
//  Ported to Swift/iOS by Shaun Harrison
//

import UIKit

private let MIN_ALPHA_SEARCH_MAX_ITERATIONS = 10
private let MIN_ALPHA_SEARCH_PRECISION = 10

internal class HexColor {
	static let WHITE = HexColor.fromRGB(255, green: 255, blue: 255)
	static let BLACK = HexColor.fromRGB(0, green: 0, blue: 0)

	/**
	:return: The alpha component of a color int.
	*/
	internal static func alpha(color: Int) -> Int {
		return color >> 24
	}

	/**
	:return: The red component of a color int.
	*/
	internal static func red(color: Int) -> Int {
		return (color >> 16) & 0xFF
	}

	/**
	:return: The green component of a color int.
	*/
	internal static func green(color: Int) -> Int {
		return (color >> 8) & 0xFF
	}

	/**
	:return: The blue component of a color int.
	*/
	internal static func blue(color: Int) -> Int {
		return color & 0xFF
	}

	/**
	Return a color-int from red, green, blue components.
	The alpha component is implicity 255 (fully opaque).
	These component values should be [0..255], but there is no
	range check performed, so if they are out of range, the
	returned color is undefined.

	:param: red  Red component [0..255] of the color
	:param: green Green component [0..255] of the color
	:param: blue  Blue component [0..255] of the color
	*/
	internal static func fromRGB(red: Int, green: Int, blue: Int) -> Int {
		return (0xFF << 24) | (red << 16) | (green << 8) | blue
	}

	/**
	Return a color-int from alpha, red, green, blue components.
	These component values should be [0..255], but there is no
	range check performed, so if they are out of range, the
	returned color is undefined.

	:param: alpha Alpha component [0..255] of the color
	:param: red   Red component [0..255] of the color
	:param: green Green component [0..255] of the color
	:param: blue  Blue component [0..255] of the color
	*/
	internal static func fromARGB(alpha: Int, red: Int, green: Int, blue: Int) -> Int {
		return (alpha << 24) | (red << 16) | (green << 8) | blue
	}

	internal static func toUIColor(color: Int) -> UIColor {
		return UIColor(red: CGFloat(self.red(color)) / 255.0, green: CGFloat(self.green(color)) / 255.0, blue: CGFloat(self.blue(color)) / 255.0, alpha: CGFloat(self.alpha(color)) / 255.0)
	}

	internal static func toRGB(color: Int) -> RGBColor {
		return RGBColor(red: self.red(color), green: self.green(color), blue: self.blue(color), alpha: self.alpha(color))
	}

	internal static func toHSL(color: Int) -> HSLColor {
		return self.toRGB(color).hsl
	}

	/** Composite two potentially translucent colors over each other and returns the result. */
	internal static func compositeColors(foreground: Int, background: Int) -> Int {
		let alpha1 = CGFloat(self.alpha(foreground)) / 255.0
		let alpha2 = CGFloat(self.alpha(background)) / 255.0

		let a = (alpha1 + alpha2) * (1.0 - alpha1)
		let r = (CGFloat(self.red(foreground)) * alpha1) + (CGFloat(self.red(background)) * alpha2 * (1.0 - alpha1))
		let g = (CGFloat(self.green(foreground)) * alpha1) + (CGFloat(self.green(background)) * alpha2 * (1.0 - alpha1))
		let b = (CGFloat(self.blue(foreground)) * alpha1) + (CGFloat(self.blue(background)) * alpha2 * (1.0 - alpha1))

		return self.fromARGB(Int(a), red: Int(r), green: Int(g), blue: Int(b))
	}

	/**
	Formula defined here: http://www.w3.org/TR/2008/REC-WCAG20-20081211/#relativeluminancedef
	
	:return: The luminance of a color
	*/
	internal static func calculateLuminance(color: Int) -> CGFloat {
		var red = CGFloat(self.red(color)) / 255.0
		red = red < 0.03928 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4)

		var green = CGFloat(self.green(color)) / 255.0
		green = green < 0.03928 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4)

		var blue = CGFloat(self.blue(color)) / 255.0
		blue = blue < 0.03928 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4)

		return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
	}

	/**
	Returns the contrast ratio between foreground and background.
	background must be opaque.

	Formula defined http://www.w3.org/TR/2008/REC-WCAG20-20081211/#contrast-ratiodef
	*/
	internal static func calculateContrast(var foreground: Int, background: Int) -> CGFloat {
		assert(self.alpha(background) == 255, "background can not be translucent")

		if self.alpha(foreground) < 255 {
			// If the foreground is translucent, composite the foreground over the background
			foreground = self.compositeColors(foreground, background: background)
		}

		let luminance1 = calculateLuminance(foreground) + 0.05
		let luminance2 = calculateLuminance(background) + 0.05

		// Now return the lighter luminance divided by the darker luminance
		return max(luminance1, luminance2) / min(luminance1, luminance2)
	}

	/**
	Calculates the minimum alpha value which can be applied to foreground so that would
	have a contrast value of at least minContrastRatio when compared to
	background.
	
	:param: foreground       the foreground color.
	:param: background       the background color. Should be opaque.
	:param: minContrastRatio the minimum contrast ratio.

	:return: the alpha value in the range 0-255, or nil if no value could be calculated.
	*/
	internal static func calculateMinimumAlpha(foreground: Int, background: Int, minContrastRatio: CGFloat) -> Int? {
		assert(self.alpha(background) == 255, "background can not be translucent")

		// First lets check that a fully opaque foreground has sufficient contrast
		var testForeground = self.setAlphaComponent(foreground, alpha: 255)
		var testRatio: CGFloat = self.calculateContrast(testForeground, background: background)
		if testRatio < minContrastRatio {
			// Fully opaque foreground does not have sufficient contrast, return error
			return nil
		}

		// Binary search to find a value with the minimum value which provides sufficient contrast
		var numIterations = 0
		var minAlpha = 0
		var maxAlpha = 255

		while numIterations <= MIN_ALPHA_SEARCH_MAX_ITERATIONS && (maxAlpha - minAlpha) > MIN_ALPHA_SEARCH_PRECISION {
			let testAlpha = (minAlpha + maxAlpha) / 2

			testForeground = self.setAlphaComponent(foreground, alpha: testAlpha)
			testRatio = self.calculateContrast(testForeground, background: background)

			if testRatio < minContrastRatio {
				minAlpha = testAlpha
			} else {
				maxAlpha = testAlpha
			}

			numIterations++
		}

		// Conservatively return the max of the range of possible alphas, which is known to pass.
		return maxAlpha
	}

	/** Set the alpha component of color to be alpha. */
	internal static func setAlphaComponent(color: Int, alpha: Int) -> Int {
		assert(alpha >= 0 && alpha <= 255, "alpha must be between 0 and 255.")
		return (color & 0x00ffffff) | (alpha << 24)
	}
	
}
