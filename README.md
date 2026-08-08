# Video Peeker Transcriber iOS

Video Peeker Transcriber is an iOS app for turning videos, links, and audio files into content that is easier to understand. It was created to make it simpler to process long videos, social media links, and voice messages without having to watch or listen to everything manually.

The app brings importing, processing, and reviewing content into one workflow: share media or paste a link, let the backend download and process it, then read the transcription, summary, and structured analysis from the app.

## Motivation

Videos, reels, YouTube links, and voice messages can require significant time and attention even when someone only needs the main idea. The app reduces that friction by making the content searchable in text, highlighting important points, and helping users decide whether the full media is worth watching or listening to.

## Features

- Import videos, links, and audio through the iOS Share Extension.
- Support for YouTube and Instagram links, as well as audio files.
- Automatic transcription with language detection.
- Summaries of processed content.
- Structured breakdowns with key points and context.
- Per-item processing status.
- Local history of imported content.
- Deletion of processed items.
- Backend connectivity and availability status.
- In-app console logs for easier diagnostics.
- YouTube cookie refresh directly on iPhone through an isolated web session when needed.
- Backend URL configuration through the app or Xcode scheme environment variables.

## Requirements

- Xcode 15 or later
- iOS 17 or later, on a device or simulator
- A running backend accessible over the network

Backend: [video-peeker-transcriber-backend](https://github.com/gabrielpc4/video-peeker-transcriber-backend)

## Running locally

1. Open `VideoPeekerTranscriber.xcodeproj` in Xcode.
2. Select the `VideoPeekerTranscriber` target.
3. Choose an iOS 17 or later simulator or device.
4. Run the project.

## Backend configuration

The default public backend URL is:

`https://videopeeker-backend.onrender.com`

To use a local backend from a physical device:

1. Open `Settings` in the app.
2. Set `Base URL` to the IP address of the machine running the backend on the same network, for example `http://192.168.0.10:8000`.

The URL can also be configured through an Xcode scheme:

- `VIDEOPEEKERTRANSCRIBER_BACKEND_BASE_URL`
- `VIDEOPEEKERTRANSCRIBER_FORCE_BACKEND_BASE_URL` (`1` or `true`)

## Project structure

- `VideoPeekerTranscriber/`: main SwiftUI and SwiftData app.
- `VideoPeekerTranscriberShareExtension/`: extension for sharing content with the app.
- `VideoPeekerTranscriber.xcodeproj/`: Xcode project.

## Notes

- The app depends on the backend to download media, transcribe content, and generate analysis.
- Processing time depends on media duration and the availability of external services.
- Noisy iOS system logs related to the keyboard or reporter may appear in the console without indicating a functional failure.

## License

This project is licensed under the [MIT License](LICENSE).

