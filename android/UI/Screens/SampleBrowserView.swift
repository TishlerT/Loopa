import SwiftUI

struct SampleBrowserView: View {
	@StateObject private var player = PreviewPlayer()
	private let client = FreesoundClient { Bundle.main.infoDictionary?["FREESOUND_API_TOKEN"] as? String }

	@State private var query: String = "piano"
	@State private var results: [Sound] = []
	@State private var page: Int = 1
	@State private var isLoading = false
	@State private var hasMoreResults = true
	@State private var errorMessage: String?
	@State private var totalCount: Int = 0

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				searchBar
				
				if let msg = errorMessage {
					Text(msg)
						.foregroundColor(.red)
						.padding(.horizontal)
				}
				
				List {
					ForEach(results) { sound in
						SoundRow(sound: sound) {
							Task { await playPreview(for: sound) }
						}
						.onAppear {
							// Trigger load more when we're near the end
							if sound.id == results.last?.id {
								Task { await loadMore() }
							}
						}
					}
					
					// Loading indicator at bottom
					if isLoading && !results.isEmpty {
						HStack {
							Spacer()
							ProgressView()
								.progressViewStyle(.circular)
							Spacer()
						}
						.listRowBackground(Color.clear)
					}
					
					// End of results indicator
					if !hasMoreResults && !results.isEmpty {
						HStack {
							Spacer()
							Text("No more results")
								.foregroundColor(.secondary)
								.font(.caption)
							Spacer()
						}
						.listRowBackground(Color.clear)
					}
				}
				.overlay {
					if isLoading && results.isEmpty {
						ProgressView("Loading...")
					}
				}
				
				// Results count footer
				if totalCount > 0 {
					Text("\(results.count) of \(totalCount) sounds")
						.font(.caption)
						.foregroundColor(.secondary)
						.padding(.vertical, 4)
				}
			}
			.navigationTitle("Freesound")
		}
		.onAppear {
			Task { await refresh() }
		}
	}
	
	// MARK: - Subviews

	private var searchBar: some View {
		HStack {
			TextField("Search sounds", text: $query)
				.textFieldStyle(.roundedBorder)
				.onSubmit {
					Task { await refresh() }
				}
			
			Button("Search") {
				Task { await refresh() }
			}
			.disabled(isLoading)
		}
		.padding()
	}
	
	// MARK: - Data Loading

	private func refresh() async {
		page = 1
		results = []
		hasMoreResults = true
		totalCount = 0
		await load()
	}
	
	private func loadMore() async {
		guard hasMoreResults, !isLoading else { return }
		page += 1
		await load()
	}

	private func load() async {
		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }
		
		do {
			let res = try await client.search(query: query, page: page, pageSize: 30)
			
			if page == 1 {
			results = res.results
			} else {
				// Append new results, avoiding duplicates
				let existingIds = Set(results.map { $0.id })
				let newResults = res.results.filter { !existingIds.contains($0.id) }
				results.append(contentsOf: newResults)
			}
			
			totalCount = res.count
			
			// Check if we've reached the end
			hasMoreResults = res.next != nil && results.count < res.count
			
			errorMessage = nil
		} catch {
			// Only show error if it's the first page
			if page == 1 {
			errorMessage = error.localizedDescription
			}
			print("Search error: \(error)")
			// If load failed, don't increment page on next attempt
			if page > 1 {
				page -= 1
			}
		}
	}
	
	// MARK: - Playback

	private func playPreview(for sound: Sound) async {
		guard let urlStr = sound.previews?["preview-hq-mp3"],
			  let url = URL(string: urlStr) else { return }
		
		do {
			try await player.play(url: url)
		} catch {
			print("Play error: \(error)")
		}
	}
}
