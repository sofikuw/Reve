# reve 

<p align="center">
<b>turn your GitHub repositories into high-speed personal cloud storage.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active-success?style=flat-square" alt="Status">
</p>

---

## Features

- **Zero Backend**: Runs 100% client-side in your browser as a single static file.
- **Multi-Account PAT Support**: Securely manage and switch between multiple GitHub accounts using Personal Access Tokens stored locally.
- **Smart Auto-Sorting Uploads**: Automatically sorts uploaded files into dedicated folders based on extensions (`images/`, `documents/`, `media/`, `archives/`, `code/`, `others/`).
- **Rich Media Previews**: View images, videos, audio, PDFs, markdown notes, and raw code instantly without forcing mandatory downloads.
- **Repository Management**: Create new public or private storage repositories directly from the interface.
- **Complete File Operations**: Upload, download, create folders, copy, move, and delete files seamlessly via the GitHub REST API.

---

## Getting Started

### Option 1: Run Locally
1. Download or clone the `index.html` file.
2. Open `index.html` in any modern web browser.

### Option 2: Host on GitHub Pages
1. Create a new public repository named `reve` (or whatever you prefer).
2. Upload the `index.html` file to the root of the repository.
3. Go to your repository **Settings > Pages**.
4. Set the source branch to `main` / `root` and save. Your cloud storage app will be live instantly!

---

## Authentication & Security

**reve** requires a GitHub **Personal Access Token (PAT)** with `repo` scope permissions. 
- Your tokens are stored entirely in your browser's local storage (`localStorage`).
- Data is communicated directly between your browser and the official GitHub REST API endpoints. No intermediary servers are involved.

---

## License

This project is placed in the public domain via the [CC0 1.0 Universal License](LICENSE). Feel free to use, modify, and distribute it however you like, with or without attribution.

