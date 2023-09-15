#!/bin/env node

if (process.argv.length <= 2) {
  console.error('No files were passed');
  process.exit(1);
}

const exec = require('child_process').exec;
const readFile = require('fs').readFile;

// First two arguments are node and this file
for (let i = 2; i < process.argv.length; i++) {
  const file = process.argv[i];
  let songs;

  readFile(file, 'utf8', (error, data) => {
    if (error) {
      console.error(error);
      return;
    }

    songs = data.split('\n').filter((line) => {
      if (line.charAt(0) !== '#' && line !== '') return line;
    });
    
    (async () => {
      songs.forEach((song) => downloadSong(song));
    })();
  });
}

let globalId = 0;

async function downloadSong(songUrl) {
  const id = globalId++;
  console.log(`Downloading ID: ${id} - ${songUrl}`);

  exec(`yt-dlp -f 'ba' -x --audio-format mp3 -o '%(title)s.%(ext)s' ${songUrl}`,
    (error, stdout, stderr) => {
      if (error) {
        console.error(error);
        return;
      }

      console.log(`Downloaded ID: ${id}`);
    });
}
