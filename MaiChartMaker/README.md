# MaiChart Maker for AstroDX

Native iOS app that imports audio, detects tempo/onsets, generates Simai-style `maidata.txt` charts for EASY, BASIC, ADVANCED, EXPERT, MASTER and Re:MASTER, and exports a song folder containing:

- `maidata.txt`
- `track.mp3`

## Inputs

- MP3 / M4A / WAV from Files
- YouTube URL through public Piped-compatible resolver instances, then on-device MP3 transcoding

YouTube access can change without notice. Local audio import is the reliable fallback. Only download media you have permission to use.

## AstroDX

In the app choose **Copy Song Folder to AstroDX/levels**, then select the AstroDX `levels` folder in the iOS Files picker.

## Build

The GitHub Actions workflow builds an unsigned IPA. Install/sign it with Feather, AltStore, SideStore or another signer using your own certificate.
