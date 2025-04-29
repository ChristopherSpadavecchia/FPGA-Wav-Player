# FPGA-Wav-Player
FPGA Wav Player by Christopher Spadavecchia &amp; Eli Shtindler<br/>
This is our final project for CPE 487 taught by Professor Bernard Yett, shoutout to him. <br/>
The goal of our project is to be able to play a .wav file on the Nexys A7 FPGA.<br/>
To be able to achieve this goal, we had to download the .wav file to a Micro SD, read the file from the Micro SD, and play back the data from the file.<br/>
## 1. Figuring out the .wav format using Python
To be able to read the .wav file format, we have to figure out how the song is formatted. To do this, we employed Python to print out information from the .wavfile.<br/>
The "WAVE" format consists of two subchunks: "fmt " and "data". The "fmt" subchunk describes the sound data's format. While, the data is the part of the song we actually want to read. <br/>


