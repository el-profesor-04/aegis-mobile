# Aegis Mobile

> **Backend & ML Infrastructure:** See [aegis-health](https://github.com/el-profesor-04/aegis-health) for the Python backend, data processing, and temporal graph database implementation.

Android mobile application for the Aegis personal health tracking and reasoning system. Built with Flutter, executes LiteRT models natively on-device with a native UI for logging, chat, graph visualization, and Phase 1 Agentic Routing.

## Overview

Aegis Mobile is a completely offline, sovereign health agent that runs on Android. It provides:

- **Real-time health event logging**: Users record symptoms, sleep, food, mood, exercise, medications
- **On-device inference**: Gemma 4 E2B and MediaPipe BERT models execute natively without cloud connectivity
- **Agentic orchestration**: Intelligent routing between data ingestion, history retrieval, and first aid RAG
- **Graph visualization**: Visual representation of health patterns and causal relationships
- **Chat interface**: Natural language query interface for health reasoning

All data remains on the user's device. No cloud synchronization, no data egress.

## Architecture

### Agentic Orchestrator

The Phase 1 Agentic Router orchestrates three core pathways:

1. **Data Ingestion Mode**: Parses user-logged health events into the temporal graph
2. **History Search Mode**: Retrieves relevant past events and patterns from the graph
3. **Offline First Aid RAG Mode**: Accesses the curated first aid knowledge base for immediate medical guidance

The router uses Gemma 4 E2B to determine which pathway to invoke based on user intent.

### On-Device Model Execution

- **Gemma 4 E2B via LiteRT-LM**: Entity extraction, query routing, answer generation
- **MediaPipe BERT Embedder**: Semantic embeddings for graph nodes and knowledge base retrieval

Both models execute natively in-process without external API calls.

### User Interface Components

- **Chat Interface**: Natural language input/output for querying the health agent
- **Event Logging**: Forms and UI flows for recording health events
- **Graph Visualization**: Visual display of temporal health patterns and causal relationships

## Getting Started

### Prerequisites

- Flutter SDK 3.0+ ([Install Flutter](https://docs.flutter.dev/get-started/install))
- Android API Level 21+
- Android Studio or Android command-line tools (for Android development)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/el-profesor-04/aegis-mobile.git
   cd aegis-mobile
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Build for Android:
   ```bash
   flutter build apk
   ```

### Running the App

Development mode:
```bash
flutter run
```

Release build:
```bash
flutter build apk --release
```

## Project Structure

```
aegis-mobile/
├── lib/
│   ├── main.dart                    # Application entry point
│   ├── features/
│   │   ├── chat/                    # Chat interface feature
│   │   ├── logging/                 # Health event logging feature
│   │   ├── graph/                   # Graph visualization feature
│   │   └── router/                  # Agentic router logic
│   ├── services/
│   │   ├── inference/               # LiteRT model inference wrapper
│   │   ├── database/                # SQLite graph database integration
│   │   └── embedding/               # MediaPipe embedder integration
│   └── models/                      # Data models and types
├── android/                         # Android-specific configuration
├── pubspec.yaml                     # Flutter dependencies
└── README.md
```

## State Management

Uses Riverpod for reactive state management across features.

## Model Files

LiteRT model files (Gemma 4 E2B, MediaPipe BERT embedder, first aid knowledge base SQLite) are bundled with the application and execute entirely on-device.

## Privacy & Security

- **Zero Cloud Connectivity**: All processing occurs locally on the device
- **No Data Egress**: Health data never leaves the user's device
- **Offline Operation**: Operates without internet connection
- **Device-Local SQLite**: All graph data persists locally in encrypted SQLite

## Development

### Adding a New Feature

Features follow clean architecture patterns with separate layers for UI, logic, and data access.

### Testing

Run tests with:
```bash
flutter test
```

## Roadmap

**Phase 1**: Agentic routing between ingestion, search, and first aid RAG

**Phase 2+**: Planned enhancements (see backlog for details)
