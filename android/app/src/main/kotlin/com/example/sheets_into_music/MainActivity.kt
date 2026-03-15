package com.example.sheets_into_music

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

class MainActivity : FlutterActivity() {
	private val pdfChannelName = "sheets_into_music/pdf"
	private val audioChannelName = "sheets_into_music/audio"

	private data class DetectedNote(
		val x: Int,
		val y: Int,
		val systemId: Int,
		val pitch: String,
		val midi: Int,
		val startMs: Int,
		val durationMs: Int,
	)

	private data class StaffModel(
		val top: Int,
		val bottom: Int,
		val spacing: Double,
		val center: Double,
		val systemId: Int,
	)

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pdfChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"analyzePdfBasic" -> {
						val pdfPath = call.argument<String>("pdfPath")
						if (pdfPath.isNullOrBlank()) {
							result.error("invalid_args", "Missing pdfPath argument.", null)
							return@setMethodCallHandler
						}

						try {
							result.success(analyzePdfBasic(pdfPath))
						} catch (e: Exception) {
							result.error("native_pdf_error", e.message, null)
						}
					}

					"renderPdfPreview" -> {
						val pdfPath = call.argument<String>("pdfPath")
						val maxWidth = call.argument<Int>("maxWidth")

						if (pdfPath.isNullOrBlank()) {
							result.error("invalid_args", "Missing pdfPath argument.", null)
							return@setMethodCallHandler
						}

						try {
							result.success(renderPdfPreview(pdfPath, maxWidth ?: 1400))
						} catch (e: Exception) {
							result.error("native_pdf_preview_error", e.message, null)
						}
					}

					else -> result.notImplemented()
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"playNotes" -> {
						@Suppress("UNCHECKED_CAST")
						val notes = call.argument<List<Map<String, Any?>>>("notes")

						if (notes == null) {
							result.error("invalid_args", "Missing notes argument.", null)
							return@setMethodCallHandler
						}

						try {
							playNotes(notes)
							result.success(true)
						} catch (e: Exception) {
							result.error("native_audio_error", e.message, null)
						}
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun analyzePdfBasic(pdfPath: String): Map<String, Any> {
		val file = File(pdfPath)
		if (!file.exists()) {
			throw IllegalArgumentException("PDF file not found at path: $pdfPath")
		}

		val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)

		var pageCount = 0
		var firstPageWidth = 0
		var firstPageHeight = 0
		val warnings = mutableListOf<String>()
		val notes = mutableListOf<Map<String, Any>>()

		descriptor.use { pfd ->
			PdfRenderer(pfd).use { renderer ->
				pageCount = renderer.pageCount
				if (pageCount <= 0) {
					warnings.add("No pages found in PDF.")
				} else {
					var timelineOffsetMs = 0

					for (pageIndex in 0 until pageCount) {
						renderer.openPage(pageIndex).use { page ->
							if (pageIndex == 0) {
								firstPageWidth = page.width
								firstPageHeight = page.height
							}

							val scale = 2
							val renderWidth = page.width * scale
							val renderHeight = page.height * scale
							val bitmap = Bitmap.createBitmap(
								renderWidth,
								renderHeight,
								Bitmap.Config.ARGB_8888,
							)

							page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

							val detected = detectNotes(bitmap)
							if (detected.isEmpty()) {
								warnings.add(
									"Page ${pageIndex + 1}: no note candidates detected."
								)
							}

							var localMaxEnd = 0
							for (note in detected) {
								val adjustedStart = note.startMs + timelineOffsetMs
								val end = adjustedStart + note.durationMs
								if (end > localMaxEnd) {
									localMaxEnd = end
								}

								notes.add(
									mapOf(
										"pitch" to note.pitch,
										"midi" to note.midi,
										"startMs" to adjustedStart,
										"durationMs" to note.durationMs,
										"x" to note.x,
										"y" to note.y,
										"pageIndex" to pageIndex,
									)
								)
							}

							timelineOffsetMs = if (localMaxEnd > timelineOffsetMs) {
								localMaxEnd + 250
							} else {
								timelineOffsetMs + 250
							}
						}
					}
				}
			}
		}

		if (notes.isNotEmpty()) {
			warnings.add("Detected ${notes.size} note candidates across $pageCount pages.")
			warnings.add("Polyphony enabled: notes aligned on the same x-position share the same start time.")
		}

		return mapOf(
			"pageCount" to pageCount,
			"firstPageWidth" to firstPageWidth,
			"firstPageHeight" to firstPageHeight,
			"notes" to notes,
			"warnings" to warnings,
			"engine" to "android_pdf_renderer_basic_cv",
		)
	}

	private fun renderPdfPreview(pdfPath: String, maxWidth: Int): Map<String, Any> {
		val file = File(pdfPath)
		if (!file.exists()) {
			throw IllegalArgumentException("PDF file not found at path: $pdfPath")
		}

		val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
		descriptor.use { pfd ->
			PdfRenderer(pfd).use { renderer ->
				if (renderer.pageCount <= 0) {
					throw IllegalStateException("PDF has no pages.")
				}

				val pages = mutableListOf<Map<String, Any>>()
				for (pageIndex in 0 until renderer.pageCount) {
					renderer.openPage(pageIndex).use { page ->
						val safeMaxWidth = max(600, maxWidth)
						val targetWidth = min(safeMaxWidth, page.width * 2)
						val scale = targetWidth.toDouble() / page.width.toDouble()
						val targetHeight = max(1, (page.height * scale).roundToInt())

						val bitmap = Bitmap.createBitmap(
							targetWidth,
							targetHeight,
							Bitmap.Config.ARGB_8888,
						)

						page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

						val output = ByteArrayOutputStream()
						bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)

						pages.add(
							mapOf(
								"pageIndex" to pageIndex,
								"pngBytes" to output.toByteArray(),
								"imageWidth" to targetWidth,
								"imageHeight" to targetHeight,
							)
						)
					}
				}

				return mapOf(
					"pages" to pages,
				)
			}
		}
	}

	private fun detectNotes(bitmap: Bitmap): List<DetectedNote> {
		val width = bitmap.width
		val height = bitmap.height
		if (width <= 0 || height <= 0) return emptyList()

		val threshold = 120
		val size = width * height
		val dark = BooleanArray(size)
		val rowCounts = IntArray(height)

		for (y in 0 until height) {
			for (x in 0 until width) {
				val pixel = bitmap.getPixel(x, y)
				val luma = (Color.red(pixel) * 299 + Color.green(pixel) * 587 + Color.blue(pixel) * 114) / 1000
				val isDark = luma < threshold
				val idx = y * width + x
				dark[idx] = isDark
				if (isDark) rowCounts[y]++
			}
		}

		val lineRows = mutableListOf<Int>()
		var y = 0
		val lineThreshold = (width * 0.45).roundToInt()
		while (y < height) {
			if (rowCounts[y] >= lineThreshold) {
				var end = y
				while (end + 1 < height && rowCounts[end + 1] >= lineThreshold) {
					end++
				}
				lineRows.add((y + end) / 2)
				y = end + 1
			} else {
				y++
			}
		}

		val staves = buildStaffModels(lineRows, height)
		if (staves.isEmpty()) return emptyList()
		val avgSpacing = staves.map { it.spacing }.average()

		val lineMask = BooleanArray(height)
		for (row in lineRows) {
			for (d in -1..1) {
				val yy = row + d
				if (yy in 0 until height) lineMask[yy] = true
			}
		}

		val visited = BooleanArray(size)
		val found = mutableListOf<DetectedNote>()

		for (yy in 0 until height) {
			for (xx in 0 until width) {
				val startIdx = yy * width + xx
				if (!dark[startIdx] || visited[startIdx] || lineMask[yy]) continue

				val queue = ArrayDeque<Int>()
				queue.add(startIdx)
				visited[startIdx] = true

				var area = 0
				var minX = xx
				var maxX = xx
				var minY = yy
				var maxY = yy
				var sumX = 0
				var sumY = 0

				while (queue.isNotEmpty()) {
					val idx = queue.removeFirst()
					val cy = idx / width
					val cx = idx % width

					area++
					sumX += cx
					sumY += cy
					minX = min(minX, cx)
					maxX = max(maxX, cx)
					minY = min(minY, cy)
					maxY = max(maxY, cy)

					for (ny in max(0, cy - 1)..min(height - 1, cy + 1)) {
						for (nx in max(0, cx - 1)..min(width - 1, cx + 1)) {
							val nIdx = ny * width + nx
							if (!visited[nIdx] && dark[nIdx] && !lineMask[ny]) {
								visited[nIdx] = true
								queue.add(nIdx)
							}
						}
					}
				}

				val boxW = maxX - minX + 1
				val boxH = maxY - minY + 1
				val cx = sumX / area
				val cy = sumY / area

				if (rowCounts[cy] > (width * 0.78)) continue

				val nearestStaff = staves.minByOrNull { abs(it.center - cy) } ?: continue
				val spacing = nearestStaff.spacing

				val staffBandTop = nearestStaff.top - (spacing * 4.8).roundToInt()
				val staffBandBottom = nearestStaff.bottom + (spacing * 4.8).roundToInt()
				if (cy < staffBandTop || cy > staffBandBottom) continue

				val minArea = max(16.0, spacing * spacing * 0.15)
				val maxArea = spacing * spacing * 7.0
				if (area < minArea || area > maxArea) continue

				if (boxW < max(4, (spacing * 0.45).roundToInt()) ||
					boxW > max(14, (spacing * 2.8).roundToInt())
				) continue
				if (boxH < max(4, (spacing * 0.45).roundToInt()) ||
					boxH > max(14, (spacing * 2.8).roundToInt())
				) continue

				val ratio = boxW.toDouble() / boxH.toDouble()
				if (ratio < 0.45 || ratio > 2.35) continue

				val fillRatio = area.toDouble() / (boxW * boxH).toDouble()
				if (fillRatio < 0.18 || fillRatio > 0.95) continue

				val hasStem = hasStemNearby(
					dark = dark,
					width = width,
					height = height,
					minX = minX,
					maxX = maxX,
					minY = minY,
					maxY = maxY,
					spacing = spacing,
				)
				val looksRounded = abs(ratio - 1.0) <= 0.9 && fillRatio >= 0.24
				if (!hasStem && !looksRounded) continue

				val step = ((nearestStaff.bottom - cy) / (spacing / 2.0)).roundToInt()
				if (abs(step) > 20) continue

				val midi = diatonicStepToMidiFromE4(step)
				val pitch = midiToName(midi)

				found.add(
					DetectedNote(
						x = cx,
						y = cy,
						systemId = nearestStaff.systemId,
						pitch = pitch,
						midi = midi,
						startMs = 0,
						durationMs = 400,
					)
				)
			}
		}

		val sorted = found.sortedWith(compareBy<DetectedNote> { it.systemId }.thenBy { it.x }.thenBy { it.y })
		if (sorted.isEmpty()) return emptyList()

		val clusterWindow = max(10, (avgSpacing * 0.85).roundToInt())
		val yDedupGap = max(4, (avgSpacing * 0.38).roundToInt())

		val systemClusters = mutableMapOf<Int, MutableList<MutableList<DetectedNote>>>()
		for (note in sorted) {
			val clusters = systemClusters.getOrPut(note.systemId) { mutableListOf() }
			if (clusters.isEmpty()) {
				clusters.add(mutableListOf(note))
				continue
			}

			val current = clusters.last()
			val anchorX = current.map { it.x }.average()
			if (abs(note.x - anchorX) <= clusterWindow) {
				current.add(note)
			} else {
				clusters.add(mutableListOf(note))
			}
		}

		val withStart = mutableListOf<DetectedNote>()
		var timeline = 0
		for (systemId in systemClusters.keys.sorted()) {
			for (cluster in systemClusters[systemId].orEmpty()) {
				val uniqueByY = mutableListOf<DetectedNote>()
				for (candidate in cluster.sortedBy { it.y }) {
					if (uniqueByY.isEmpty() || abs(candidate.y - uniqueByY.last().y) > yDedupGap) {
						uniqueByY.add(candidate)
					}
				}

				for (note in uniqueByY) {
					withStart.add(note.copy(startMs = timeline))
				}

				timeline += 400
			}
		}

		return withStart.take(128)
	}

	private fun buildStaffModels(lineRows: List<Int>, imageHeight: Int): List<StaffModel> {
		if (lineRows.size < 5) {
			return emptyList()
		}

		val candidates = mutableListOf<Triple<Int, Int, Double>>()
		for (i in 0..(lineRows.size - 5)) {
			val section = lineRows.subList(i, i + 5)
			val diffs = IntArray(4)
			for (d in 0 until 4) {
				diffs[d] = section[d + 1] - section[d]
			}

			val avg = diffs.average()
			if (avg < 4.0 || avg > max(80.0, imageHeight / 8.0)) continue

			var variance = 0.0
			for (diff in diffs) {
				variance += (diff - avg).pow(2)
			}
			if (variance > 32.0) continue

			candidates.add(Triple(section.first(), section.last(), avg))
		}

		if (candidates.isEmpty()) return emptyList()

		val merged = mutableListOf<Triple<Int, Int, Double>>()
		for (candidate in candidates.sortedBy { it.first }) {
			if (merged.isEmpty()) {
				merged.add(candidate)
				continue
			}

			val last = merged.last()
			if (abs(candidate.first - last.first) <= 6) {
				if ((candidate.third + 0.0001) < last.third) {
					merged[merged.lastIndex] = candidate
				}
			} else {
				merged.add(candidate)
			}
		}

		val staffModels = merged.map {
			StaffModel(
				top = it.first,
				bottom = it.second,
				spacing = it.third,
				center = (it.first + it.second) / 2.0,
				systemId = 0,
			)
		}.toMutableList()

		var currentSystem = 0
		for (index in staffModels.indices) {
			if (index > 0) {
				val gap = staffModels[index].top - staffModels[index - 1].bottom
				val allowed = max(staffModels[index - 1].spacing, staffModels[index].spacing) * 8.0
				if (gap > allowed) {
					currentSystem++
				}
			}

			staffModels[index] = staffModels[index].copy(systemId = currentSystem)
		}

		return staffModels
	}

	private fun hasStemNearby(
		dark: BooleanArray,
		width: Int,
		height: Int,
		minX: Int,
		maxX: Int,
		minY: Int,
		maxY: Int,
		spacing: Double,
	): Boolean {
		val probeMinX = max(0, minX - (spacing * 0.7).roundToInt())
		val probeMaxX = min(width - 1, maxX + (spacing * 0.7).roundToInt())
		val probeMinY = max(0, minY - (spacing * 3.2).roundToInt())
		val probeMaxY = min(height - 1, maxY + (spacing * 3.2).roundToInt())
		val minRun = max(6, (spacing * 1.9).roundToInt())

		for (x in probeMinX..probeMaxX) {
			var run = 0
			for (y in probeMinY..probeMaxY) {
				val idx = y * width + x
				if (dark[idx]) {
					run++
					if (run >= minRun) {
						return true
					}
				} else {
					run = 0
				}
			}
		}

		return false
	}

	private fun estimateStaffReference(lineRows: List<Int>, imageHeight: Int): Pair<Int, Double> {
		if (lineRows.size < 5) {
			return Pair((imageHeight * 0.65).roundToInt(), max(10.0, imageHeight / 60.0))
		}

		var bestStart = 0
		var bestScore = Double.MAX_VALUE
		var bestSpacing = max(10.0, imageHeight / 60.0)

		for (i in 0..(lineRows.size - 5)) {
			val section = lineRows.subList(i, i + 5)
			val diffs = IntArray(4)
			for (d in 0 until 4) {
				diffs[d] = section[d + 1] - section[d]
			}
			val avg = diffs.average()
			if (avg < 4.0 || avg > 80.0) continue

			var variance = 0.0
			for (diff in diffs) {
				variance += (diff - avg).pow(2)
			}

			if (variance < bestScore) {
				bestScore = variance
				bestStart = i
				bestSpacing = avg
			}
		}

		val bestSet = lineRows.subList(bestStart, bestStart + 5)
		val bottomLine = bestSet[4]
		return Pair(bottomLine, bestSpacing)
	}

	private fun diatonicStepToMidiFromE4(step: Int): Int {
		var degree = 0 // E
		var midi = 64 // E4
		val upIntervals = intArrayOf(1, 2, 2, 2, 1, 2, 2) // E->F->G->A->B->C->D->E

		if (step > 0) {
			repeat(step) {
				midi += upIntervals[degree]
				degree = (degree + 1) % 7
			}
		} else if (step < 0) {
			repeat(-step) {
				val previousDegree = (degree + 6) % 7
				midi -= upIntervals[previousDegree]
				degree = previousDegree
			}
		}

		return midi.coerceIn(36, 96)
	}

	private fun midiToName(midi: Int): String {
		val names = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
		val noteName = names[midi % 12]
		val octave = (midi / 12) - 1
		return "$noteName$octave"
	}

	private fun playNotes(notes: List<Map<String, Any?>>) {
		if (notes.isEmpty()) return

		val sampleRate = 44100

		data class PlaybackNote(val midi: Int, val startMs: Int, val durationMs: Int)
		val events = notes.map { raw ->
			PlaybackNote(
				midi = ((raw["midi"] as? Number)?.toInt() ?: 60).coerceIn(24, 108),
				startMs = ((raw["startMs"] as? Number)?.toInt() ?: 0).coerceAtLeast(0),
				durationMs = ((raw["durationMs"] as? Number)?.toInt() ?: 400).coerceAtLeast(80),
			)
		}

		val totalMs = events.maxOf { it.startMs + it.durationMs } + 120
		val totalSamples = ((totalMs / 1000.0) * sampleRate).roundToInt().coerceAtLeast(1)
		val mix = DoubleArray(totalSamples)

		for (event in events) {
			val frequency = 440.0 * 2.0.pow((event.midi - 69) / 12.0)
			val startSample = ((event.startMs / 1000.0) * sampleRate).roundToInt()
			val sampleCount = ((event.durationMs / 1000.0) * sampleRate).roundToInt().coerceAtLeast(1)
			val fadeSamples = min(260, sampleCount / 8).coerceAtLeast(1)

			for (i in 0 until sampleCount) {
				val outIndex = startSample + i
				if (outIndex >= totalSamples) break

				val envelope = when {
					i < fadeSamples -> i.toDouble() / fadeSamples
					i > sampleCount - fadeSamples ->
						(sampleCount - i).toDouble() / fadeSamples
					else -> 1.0
				}

				val sample = sin(2.0 * PI * frequency * i / sampleRate) * 0.22 * envelope
				mix[outIndex] += sample
			}
		}

		var peak = 0.0
		for (value in mix) {
			peak = max(peak, abs(value))
		}
		val normalizer = if (peak > 1.0) 1.0 / peak else 1.0

		val pcm = ByteArray(totalSamples * 2)
		for (i in mix.indices) {
			val clamped = (mix[i] * normalizer).coerceIn(-1.0, 1.0)
			val value = (clamped * Short.MAX_VALUE).roundToInt().toShort()
			pcm[i * 2] = (value.toInt() and 0xFF).toByte()
			pcm[i * 2 + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
		}

		val minBuffer = AudioTrack.getMinBufferSize(
			sampleRate,
			AudioFormat.CHANNEL_OUT_MONO,
			AudioFormat.ENCODING_PCM_16BIT,
		)

		val track = AudioTrack(
			AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_MEDIA)
				.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
				.build(),
			AudioFormat.Builder()
				.setEncoding(AudioFormat.ENCODING_PCM_16BIT)
				.setSampleRate(sampleRate)
				.setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
				.build(),
			max(minBuffer, pcm.size),
			AudioTrack.MODE_STATIC,
			AudioManager.AUDIO_SESSION_ID_GENERATE,
		)

		track.write(pcm, 0, pcm.size)
		track.play()

		val writtenSamples = pcm.size / 2
		while (track.playState == AudioTrack.PLAYSTATE_PLAYING &&
			track.playbackHeadPosition < writtenSamples
		) {
			Thread.sleep(20)
		}

		track.stop()
		track.release()
	}
}
