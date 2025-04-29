# FPGA-Wav-Player
FPGA Wav Player by Christopher Spadavecchia &amp; Eli Shtindler

This is our final project for CPE 487 taught by Professor Bernard Yett, shoutout to him. 

The goal of our project is to be able to play a .wav file on the Nexys A7 FPGA.

To be able to achieve this goal, we had to download the .wav file to a Micro SD, read the file from the Micro SD, and play back the data from the file.
## 1. Figuring out the .wav (Wave) format using Python
To be able to read the Wave file format, we have to figure out how the song is formatted. To do this, we employed Python to extract and print out information from the .wavfile.

All the information that we used for the Wave file format, we found on this webiste: [WAVE PCM soundfile format](http://soundfile.sapp.org/doc/WaveFormat/).

The WAVE format is a part of Microsoft’s RIFF(Resource Interchange File Format) standard for multimedia file storage.

A RIFF file starts out with a file header followed by a sequence of data chunks. A WAVE file is often just a RIFF file with a single "WAVE" chunk which consists of two sub-chunks: a "fmt "chunk which describes the sound data's format and a "data" chunk containing the actual song data that we want to read.

From the "fmt" chunk we had to extract certain components to figure out the format of the song data.

We started by looking at the NumChannels component which would determine if it was 1 = Mono or 2 = Stereo.
