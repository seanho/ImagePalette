//
//  ColorCutQuantizer.swift
//  ImagePalette
//
//  Original created by Google/Android
//  Ported to Swift/iOS by Shaun Harrison
//

import Foundation
import UIKit
import SwiftPriorityQueue

private let COMPONENT_RED = -3
private let COMPONENT_GREEN = -2
private let COMPONENT_BLUE = -1

private let BLACK_MAX_LIGHTNESS = CGFloat(0.05)
private let WHITE_MIN_LIGHTNESS = CGFloat(0.95)

private typealias VboxPriorityQueue = PriorityQueue<Vbox>

internal final class ColorCutQuantizer {

	private var colors = Array<Int>()
	private var colorPopulations = Dictionary<Int, Int>()

	/** list of quantized colors */
	private(set) var quantizedColors = Array<PaletteSwatch>()

	/**
	Factory-method to generate a ColorCutQuantizer from a UIImage.

	:param: image Image to extract the pixel data from
	:param: maxColors The maximum number of colors that should be in the result palette.
	*/
	internal static func fromImage(image: UIImage, maxColors: Int) -> ColorCutQuantizer {
		let pixels = image.pixels
		return ColorCutQuantizer(colorHistogram: ColorHistogram(pixels: pixels), maxColors: maxColors)
	}

	/**
	:param: colorHistogram histogram representing an image's pixel data
	:param maxColors The maximum number of colors that should be in the result palette.
	*/
	private init(colorHistogram: ColorHistogram, maxColors: Int) {
		let rawColorCount = colorHistogram.numberOfColors
		let rawColors = colorHistogram.colors
		let rawColorCounts = colorHistogram.colorCounts

		// First, lets pack the populations into a SparseIntArray so that they can be easily
		// retrieved without knowing a color's index
		self.colorPopulations = Dictionary(minimumCapacity: rawColorCount)
		for (var i = 0; i < rawColors.count; i++) {
			self.colorPopulations[rawColors[i]] = rawColorCounts[i]
		}

		// Now go through all of the colors and keep those which we do not want to ignore
		var validColorCount = 0
		self.colors = Array()
		self.colors.reserveCapacity(rawColorCount)

		for color in rawColors {
			if !self.shouldIgnoreColor(color) {
				self.colors.append(color)
				validColorCount++
			}
		}

		if (validColorCount <= maxColors) {
			// The image has fewer colors than the maximum requested, so just return the colors
			self.quantizedColors = Array()
			for color in self.colors {
				if let populations = self.colorPopulations[color] {
					self.quantizedColors.append(PaletteSwatch(color: HexColor.toUIColor(color), population: populations))
				}
			}
		} else {
			// We need use quantization to reduce the number of colors
			self.quantizedColors = self.quantizePixels(validColorCount - 1, maxColors: maxColors)
		}
	}

	private func quantizePixels(maxColorIndex: Int, maxColors: Int) -> [PaletteSwatch] {
		// Create the priority queue which is sorted by volume descending. This means we always
		// split the largest box in the queue
		var pq = PriorityQueue<Vbox>(ascending: false, startingValues: Array())

		// final PriorityQueue<Vbox> pq = PriorityQueue<Vbox>(maxColors, VBOX_COMPARATOR_VOLUME)

		// To start, offer a box which contains all of the colors
		pq.push(Vbox(quantizer: self, lowerIndex: 0, upperIndex: maxColorIndex))

		// Now go through the boxes, splitting them until we have reached maxColors or there are no
		// more boxes to split
		self.splitBoxes(&pq, maxSize: maxColors)

		// Finally, return the average colors of the color boxes
		return generateAverageColors(pq)
	}

	/**
	Iterate through the Queue, popping Vbox objects from the queue and splitting them. Once
	split, the new box and the remaining box are offered back to the queue.

	:param: queue Priority queue to poll for boxes
	:param: maxSize Maximum amount of boxes to split
	*/
	private func splitBoxes(inout queue: VboxPriorityQueue, maxSize: Int) {
		while queue.count < maxSize {
			if let vbox = queue.pop() where vbox.canSplit {
				// First split the box, and offer the result
				queue.push(vbox.splitBox())
				// Then offer the box back
				queue.push(vbox)
			} else {
				// If we get here then there are no more boxes to split, so return
				return
			}
		}
	}

	private func generateAverageColors(vboxes: VboxPriorityQueue) -> [PaletteSwatch] {
		var colors = Array<PaletteSwatch>()

		for vbox in vboxes {
			let color = vbox.averageColor
			
			if (!self.dynamicType.shouldIgnoreColor(color)) {
				// As we're averaging a color box, we can still get colors which we do not want, so
				// we check again here
				colors.append(color)
			}
		}

		return colors
	}

	/**
	Modify the significant octet in a packed color int. Allows sorting based on the value of a
	single color component.
	*/
	private func modifySignificantOctet(dimension: Int, lowerIndex: Int, upperIndex: Int) {
		switch (dimension) {
			case COMPONENT_RED:
				// Already in RGB, no need to do anything
				break

			case COMPONENT_GREEN:
				// We need to do a RGB to GRB swap, or vice-versa
				for var i = lowerIndex; i <= upperIndex; i++ {
					let color = self.colors[i]
					self.colors[i] = HexColor.fromRGB((color >> 8) & 0xFF, green: (color >> 16) & 0xFF, blue: color & 0xFF)
				}
			case COMPONENT_BLUE:
				// We need to do a RGB to BGR swap, or vice-versa
				for var i = lowerIndex; i <= upperIndex; i++ {
					let color = self.colors[i]
					self.colors[i] = HexColor.fromRGB(color & 0xFF, green: (color >> 8) & 0xFF, blue: (color >> 16) & 0xFF)
				}
			default:
				break
		}
	}

	private func shouldIgnoreColor(color: Int) -> Bool {
		let hsl = HexColor.toHSL(color)
		return self.dynamicType.shouldIgnoreColor(hsl)
	}

	private static func shouldIgnoreColor(color: PaletteSwatch) -> Bool {
		return self.shouldIgnoreColor(color.hsl)
	}

	private static func shouldIgnoreColor(hslColor: HSLColor) -> Bool {
		return self.isWhite(hslColor) || self.isBlack(hslColor) || self.isNearRedILine(hslColor)
	}

	/**
	:return: true if the color represents a color which is close to black.
	*/
	private static func isBlack(hslColor: HSLColor) -> Bool {
		return hslColor.lightness <= BLACK_MAX_LIGHTNESS
	}

	/**
	:return: true if the color represents a color which is close to white.
	*/
	private static func isWhite(hslColor: HSLColor) -> Bool {
		return hslColor.lightness >= WHITE_MIN_LIGHTNESS
	}

	/**
	:return: true if the color lies close to the red side of the I line.
	*/
	private static func isNearRedILine(hslColor: HSLColor) -> Bool {
		return hslColor.hue >= 10.0 && hslColor.hue <= 37.0 && hslColor.saturation <= 0.82
	}

}

/** Represents a tightly fitting box around a color space. */
private class Vbox: Hashable {
	// lower and upper index are inclusive
	private let lowerIndex: Int
	private var upperIndex: Int

	private var minRed = 0
	private var maxRed = 0

	private var minGreen = 0
	private var maxGreen = 0

	private var minBlue = 0
	private var maxBlue = 0

	private let quantizer: ColorCutQuantizer

	private static var ordinal = 0

	let hashValue = ++Vbox.ordinal

	init(quantizer: ColorCutQuantizer, lowerIndex: Int, upperIndex: Int) {
		self.quantizer = quantizer

		self.lowerIndex = lowerIndex
		self.upperIndex = upperIndex
		assert(self.lowerIndex <= self.upperIndex, "lowerIndex (\(self.lowerIndex)) can’t be > upperIndex (\(self.upperIndex))")
		self.fitBox()
	}

	var volume: Int {
		return (self.maxRed - self.minRed + 1) * (self.maxGreen - self.minGreen + 1) * (self.maxBlue - self.minBlue + 1)
	}

	var canSplit: Bool {
		return self.colorCount > 1
	}

	var colorCount: Int {
		return self.upperIndex - self.lowerIndex + 1
	}

	/** Recomputes the boundaries of this box to tightly fit the colors within the box. */
	func fitBox() {
		// Reset the min and max to opposite values
		self.minRed = 0xFF
		self.minGreen = 0xFF
		self.minBlue = 0xFF

		self.maxRed = 0x0
		self.maxGreen = 0x0
		self.maxBlue = 0x0

		for var i = self.lowerIndex; i <= self.upperIndex; i++ {
			let color = HexColor.toRGB(self.quantizer.colors[i])

			self.maxRed = max(self.maxRed, color.red)
			self.minRed = min(self.minRed, color.red)

			self.maxGreen = max(self.maxGreen, color.green)
			self.minGreen = min(self.minGreen, color.green)

			self.maxBlue = max(self.maxBlue, color.blue)
			self.minBlue = min(self.minBlue, color.blue)
		}
	}

	/**
	Split this color box at the mid-point along it's longest dimension
	
	:return: the new ColorBox
	*/
	func splitBox() -> Vbox {
		if (!self.canSplit) {
			fatalError("Can not split a box with only 1 color")
		}

		// find median along the longest dimension
		let splitPoint = self.findSplitPoint()

		assert(splitPoint + 1 <= self.upperIndex, "splitPoint (\(splitPoint + 1)) can’t be > upperIndex (\(self.upperIndex)), lowerIndex: \(self.lowerIndex)")

		let newBox = Vbox(quantizer: self.quantizer, lowerIndex: splitPoint + 1, upperIndex: self.upperIndex)

		// Now change this box's upperIndex and recompute the color boundaries
		self.upperIndex = splitPoint
		assert(self.lowerIndex <= self.upperIndex, "lowerIndex (\(self.lowerIndex)) can’t be > upperIndex (\(self.upperIndex))")
		self.fitBox()

		return newBox
	}

	/**
	:return: the dimension which this box is largest in
	*/
	var longestColorDimension: Int {
		let redLength = self.maxRed - self.minRed
		let greenLength = self.maxGreen - self.minGreen
		let blueLength = self.maxBlue - self.minBlue

		if redLength >= greenLength && redLength >= blueLength {
			return COMPONENT_RED
		} else if greenLength >= redLength && greenLength >= blueLength {
			return COMPONENT_GREEN
		} else {
			return COMPONENT_BLUE
		}
	}

	/**
	Finds the point within this box's lowerIndex and upperIndex index of where to split.

	This is calculated by finding the longest color dimension, and then sorting the
	sub-array based on that dimension value in each color. The colors are then iterated over
	until a color is found with at least the midpoint of the whole box's dimension midpoint.

	:return: the index of the colors array to split from
	*/
	func findSplitPoint() -> Int {
		let longestDimension = self.longestColorDimension

		// Sort the colors in this box based on the longest color dimension.

		var sorted = self.quantizer.colors[self.lowerIndex...self.upperIndex]
		sorted.sortInPlace()

		if longestDimension == COMPONENT_RED {
			sorted.sortInPlace() {
				return HexColor.red($0) < HexColor.red($1)
			}
		} else if longestDimension == COMPONENT_GREEN {
			sorted.sortInPlace() {
				return HexColor.green($0) < HexColor.green($1)
			}
		} else  {
			sorted.sortInPlace() {
				return HexColor.blue($0) < HexColor.blue($1)
			}
		}

		self.quantizer.colors[self.lowerIndex...self.upperIndex] = sorted

		let dimensionMidPoint = self.midPoint(longestDimension)

		for var i = self.lowerIndex; i < self.upperIndex; i++  {
			let color = self.quantizer.colors[i]

			switch (longestDimension) {
				case COMPONENT_RED where HexColor.red(color) >= dimensionMidPoint:
					return i
				case COMPONENT_GREEN where HexColor.green(color) >= dimensionMidPoint:
					return i
				case COMPONENT_BLUE where HexColor.blue(color) > dimensionMidPoint:
					return i
				default:
					continue
			}
		}

		return self.lowerIndex
	}

	/**
	* @return the average color of this box.
	*/
	var averageColor: PaletteSwatch {
		var redSum = 0
		var greenSum = 0
		var blueSum = 0
		var totalPopulation = 0

		for var i = self.lowerIndex; i <= self.upperIndex; i++ {
			let color = self.quantizer.colors[i]

			if let colorPopulation = self.quantizer.colorPopulations[color] {
				totalPopulation += colorPopulation
				redSum += colorPopulation * HexColor.red(color)
				greenSum += colorPopulation * HexColor.green(color)
				blueSum += colorPopulation * HexColor.blue(color)
			}
		}

		let redAverage = Int(round(Double(redSum) / Double(totalPopulation)))
		let greenAverage = Int(round(Double(greenSum) / Double(totalPopulation)))
		let blueAverage = Int(round(Double(blueSum) / Double(totalPopulation)))

		return PaletteSwatch(rgbColor: RGBColor(red: redAverage, green: greenAverage, blue: blueAverage, alpha: 255), population: totalPopulation)
	}

	/**
	* @return the midpoint of this box in the given {@code dimension}
	*/
	func midPoint(dimension: Int) -> Int {
		switch (dimension) {
			case COMPONENT_GREEN:
				return (self.minGreen + self.maxGreen) / 2
			case COMPONENT_BLUE:
				return (self.minBlue + self.maxBlue) / 2
			case COMPONENT_RED:
				return (self.minRed + self.maxRed) / 2
			default:
				return (self.minRed + self.maxRed) / 2
		}
	}
}

extension Vbox: Comparable { }

private func ==(lhs: Vbox, rhs: Vbox) -> Bool {
	return lhs.hashValue == rhs.hashValue
}

private func <=(lhs: Vbox, rhs: Vbox) -> Bool {
	return lhs.volume <= rhs.volume
}

private func >=(lhs: Vbox, rhs: Vbox) -> Bool {
	return lhs.volume >= rhs.volume
}

private func <(lhs: Vbox, rhs: Vbox) -> Bool {
	return lhs.volume < rhs.volume
}

private func >(lhs: Vbox, rhs: Vbox) -> Bool {
	return lhs.volume > rhs.volume
}
