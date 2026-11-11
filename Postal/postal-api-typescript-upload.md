# Postal.Api — TypeScript Upload Page

**Target path:** `src/Postal.Api/Pages/UploadTs/`  
**Version:** 1.0 · 2026-11-10  
**Scope:** Client-side only. Backend remains the existing .NET `Postal.Api` (`/api/imports` endpoints).

## Summary

`Upload.cshtml` is a self-contained HTML page with embedded CSS and ~250 lines of vanilla JavaScript.  
`Upload.cshtml.cs` is an empty `PageModel` (no server logic).

**Conversion approach (Option A):**
- Pure static HTML + TypeScript client.
- Same API contract (`POST /api/imports`, SAS PUT, `POST /complete`, `GET` poll).
- No Node server, no Express, no Azure Function required.
- Drop-in replacement for the Razor page.

## Target Structure

```
src/Postal.Api/Pages/UploadTs/
├── UploadTs.html          # markup + styles (no inline JS)
├── UploadTs.ts            # upload logic
├── UploadTs.css           # (optional extract; styles can stay in HTML)
└── tsconfig.json          # minimal for the page
```

Compiled `UploadTs.js` is served alongside the HTML.  
Azure App Service / ASP.NET Core can serve these as static files (or a thin Razor page that only returns the HTML).

## API Contract (unchanged)

| Step | Method | Endpoint | Body / Notes |
|------|--------|----------|--------------|
| 1 | `POST` | `/api/imports` | `{ originalFileName, sizeBytes }` → `{ jobId, sasUrl, ... }` |
| 2 | `PUT` | SAS URL | Block blob upload with `x-ms-blob-type: BlockBlob` + progress |
| 3 | `POST` | `/api/imports/{jobId}/complete` | empty body |
| 4 | `GET` | `/api/imports/{jobId}` | poll every 2 s (max 1 h) until `Succeeded` / `Failed` |

## Implementation

### UploadTs.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Postal File Upload</title>
  <link rel="icon" type="image/x-icon" href="~/images/favicon.ico" />
  <link rel="stylesheet" href="UploadTs.css">
</head>
<body>
  <div class="container">
    <div class="brand">
      <img src="~/images/logo.png" alt="Postal logo" class="brand-logo" />
      <h1>📬 Postal File Upload</h1>
    </div>
    <p class="subtitle">Import fixed-width postal records to Azure SQL</p>

    <div id="alertContainer"></div>

    <div id="uploadSection">
      <div class="upload-section">
        <div class="file-input-wrapper">
          <input type="file" id="fileInput" accept=".wrk,.txt">
          <label for="fileInput" class="file-input-label">
            <div style="font-size: 32px; margin-bottom: 10px;">📁</div>
            <span class="text">Choose a file or drag and drop</span>
            <span class="hint">Supported: .wrk (CRLF) or .txt (raw) files up to 10 GB</span>
          </label>
        </div>
        <div id="fileNameDisplay"></div>
      </div>
      <div class="button-group">
        <button class="btn-upload" id="uploadBtn" disabled>Start Upload</button>
        <button class="btn-clear" id="clearBtn">Clear</button>
      </div>
    </div>

    <div id="statusSection" class="status-section">
      <div class="status-box">
        <div class="status-field"><label>Job ID:</label><value id="jobIdDisplay">-</value></div>
        <div class="status-field"><label>File:</label><value id="fileNameStatusDisplay">-</value></div>
        <div class="status-field"><label>File Size:</label><value id="fileSizeDisplay">-</value></div>
        <div class="status-field"><label>Status:</label><value id="statusDisplay">-</value></div>
        <div class="status-field"><label>Rows Written:</label><value id="rowsWrittenDisplay">0</value></div>
        <div id="progressContainer" style="display: none;">
          <label style="display: block; margin-bottom: 8px; font-weight: 600; font-size: 14px;">Upload Progress:</label>
          <div class="progress-bar"><div class="progress-fill" id="uploadProgressBar"></div></div>
          <div style="text-align: right; font-size: 12px; color: #666; margin-top: 4px;">
            <span id="progressPercent">0%</span>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script type="module" src="UploadTs.js"></script>
</body>
</html>
```

### UploadTs.ts

```typescript
interface ImportJob {
  jobId: string;
  originalFileName?: string;
  sizeBytes?: number;
  status?: string;
  rowsWritten?: number;
  error?: string;
  sasUrl?: string;
}

const fileInput = document.getElementById("fileInput") as HTMLInputElement;
const fileNameDisplay = document.getElementById("fileNameDisplay")!;
const uploadBtn = document.getElementById("uploadBtn") as HTMLButtonElement;
const clearBtn = document.getElementById("clearBtn") as HTMLButtonElement;
const uploadSection = document.getElementById("uploadSection")!;
const statusSection = document.getElementById("statusSection")!;
const alertContainer = document.getElementById("alertContainer")!;

let selectedFile: File | null = null;
let currentJobId: string | null = null;

fileInput.addEventListener("change", () => {
  selectedFile = fileInput.files?.[0] ?? null;
  updateFileDisplay();
});

const label = document.querySelector(".file-input-label")!;
["dragenter", "dragover", "dragleave", "drop"].forEach((evt) =>
  label.addEventListener(evt, (e) => {
    e.preventDefault();
    e.stopPropagation();
  })
);
["dragenter", "dragover"].forEach((evt) =>
  label.addEventListener(evt, () => {
    (label as HTMLElement).style.borderColor = "#764ba2";
    (label as HTMLElement).style.backgroundColor = "#f0e6ff";
  })
);
["dragleave", "drop"].forEach((evt) =>
  label.addEventListener(evt, () => {
    (label as HTMLElement).style.borderColor = "#667eea";
    (label as HTMLElement).style.backgroundColor = "#f8f9ff";
  })
);
label.addEventListener("drop", (e: DragEvent) => {
  const files = e.dataTransfer?.files;
  if (files?.length) {
    fileInput.files = files;
    selectedFile = files[0];
    updateFileDisplay();
  }
});

function updateFileDisplay(): void {
  if (selectedFile) {
    fileNameDisplay.textContent = `📄 ${selectedFile.name} (${formatBytes(selectedFile.size)})`;
    fileNameDisplay.style.display = "block";
    uploadBtn.disabled = false;
  } else {
    fileNameDisplay.style.display = "none";
    uploadBtn.disabled = true;
  }
}

clearBtn.addEventListener("click", () => {
  selectedFile = null;
  fileInput.value = "";
  updateFileDisplay();
  hideAlert();
});

uploadBtn.addEventListener("click", startUpload);

async function startUpload(): Promise<void> {
  if (!selectedFile) return;

  uploadBtn.disabled = true;
  clearBtn.disabled = true;

  try {
    showAlert("Initializing upload...", "info");

    const initRes = await fetch("/api/imports", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        originalFileName: selectedFile.name,
        sizeBytes: selectedFile.size,
      }),
    });
    if (!initRes.ok) throw new Error(`Failed to initialize import: ${initRes.statusText}`);

    const job = (await initRes.json()) as ImportJob;
    currentJobId = job.jobId;

    showAlert("Upload initialized. Starting file upload to blob storage...", "info");
    showStatusSection();
    updateStatusDisplay(job);

    if (!job.sasUrl) throw new Error("No SAS URL provided");

    document.getElementById("progressContainer")!.style.display = "block";
    await uploadViaSasPut(job.sasUrl, selectedFile, (pct) => {
      (document.getElementById("uploadProgressBar") as HTMLElement).style.width = pct + "%";
      document.getElementById("progressPercent")!.textContent = pct + "%";
    });

    showAlert("File uploaded successfully. Notifying server...", "success");

    const completeRes = await fetch(`/api/imports/${currentJobId}/complete`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
    });
    if (!completeRes.ok) throw new Error(`Failed to complete import: ${completeRes.statusText}`);

    showAlert("Upload complete! Processing your file...", "success");
    await pollJobStatus();
  } catch (err) {
    console.error("Upload error:", err);
    showAlert(`Error: ${(err as Error).message}`, "error");
    uploadBtn.disabled = false;
    clearBtn.disabled = false;
  }
}

async function pollJobStatus(): Promise<void> {
  const maxRetries = 1800;
  const intervalMs = 2000;
  let retries = 0;

  while (retries < maxRetries && currentJobId) {
    try {
      const res = await fetch(`/api/imports/${currentJobId}`);
      if (!res.ok) throw new Error("Failed to fetch job status");

      const job = (await res.json()) as ImportJob;
      updateStatusDisplay(job);

      if (job.status === "Succeeded") {
        showAlert(`✅ Import succeeded! ${job.rowsWritten ?? 0} rows written.`, "success");
        uploadSection.style.display = "none";
        break;
      }
      if (job.status === "Failed") {
        showAlert(`❌ Import failed: ${job.error ?? "unknown"}`, "error");
        break;
      }

      const elapsedMin = Math.floor((retries * intervalMs) / 60000);
      if (retries % 15 === 0 && retries > 0) {
        showAlert(`Still processing… (${elapsedMin} min elapsed)`, "info");
      }

      await new Promise((r) => setTimeout(r, intervalMs));
      retries++;
    } catch (err) {
      console.error("Status poll error:", err);
      retries++;
    }
  }

  if (retries >= maxRetries) {
    showAlert("Polling timed out. Check the job status later.", "warning");
  }

  uploadBtn.disabled = false;
  clearBtn.disabled = false;
}

function updateStatusDisplay(job: ImportJob): void {
  document.getElementById("jobIdDisplay")!.textContent = job.jobId ?? "-";
  document.getElementById("fileNameStatusDisplay")!.textContent = job.originalFileName ?? "-";
  document.getElementById("fileSizeDisplay")!.textContent = formatBytes(job.sizeBytes ?? 0);
  document.getElementById("rowsWrittenDisplay")!.textContent = String(job.rowsWritten ?? 0);

  const status = job.status ?? "Unknown";
  const statusEl = document.getElementById("statusDisplay")!;
  statusEl.innerHTML = `<span class="job-status status-${status.toLowerCase()}">${status}</span>`;
}

function showStatusSection(): void {
  const section = uploadSection.querySelector(".upload-section") as HTMLElement | null;
  if (section) section.style.display = "none";
  statusSection.style.display = "block";
}

function showAlert(message: string, type: "info" | "success" | "error" | "warning"): void {
  alertContainer.innerHTML = `<div class="alert alert-${type}">${message}</div>`;
}

function hideAlert(): void {
  alertContainer.innerHTML = "";
}

function uploadViaSasPut(
  sasUrl: string,
  file: File,
  onProgress: (percent: number) => void
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", sasUrl, true);
    xhr.setRequestHeader("x-ms-blob-type", "BlockBlob");
    xhr.setRequestHeader("Content-Type", "application/octet-stream");

    xhr.upload.onprogress = (evt) => {
      if (evt.lengthComputable) {
        onProgress(Math.round((evt.loaded / evt.total) * 100));
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`Blob upload failed (${xhr.status}): ${xhr.responseText || "No response body"}`));
    };
    xhr.onerror = () => reject(new Error("Blob upload network error"));
    xhr.send(file);
  });
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 Bytes";
  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + " " + sizes[i];
}
```

### UploadTs.css

Copy the `<style>` block from the original `Upload.cshtml` into this file (unchanged).

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "strict": true,
    "outDir": ".",
    "rootDir": ".",
    "lib": ["ES2022", "DOM"]
  },
  "files": ["UploadTs.ts"]
}
```

## Build & Serve

```bash
npx tsc -p src/Postal.Api/Pages/UploadTs/tsconfig.json
```

Serve `UploadTs.html` + `UploadTs.js` + `UploadTs.css` as static content.  
A minimal Razor page can simply return the HTML file if a route is still required.

## Acceptance

- File selection + drag/drop works.
- `POST /api/imports` returns job + SAS.
- XHR PUT reports progress.
- `POST /complete` is called.
- Status polls every 2 s until terminal state or 1 h timeout.
- UI matches original (alerts, progress, status badges).

No server-side TypeScript is required. The empty `UploadModel` is discarded.