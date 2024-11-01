#!/bin/bash

# Tjekker, om scriptet kører som root
if [[ $EUID -ne 0 ]]; then
   echo "Dette script skal køres som root. Brug sudo." 
   exit 1
fi

# Opdater og opgrader systempakker
echo "Opdaterer og opgraderer alle systempakker..."
apt update && apt upgrade -y || {
    echo "Fejl ved opdatering af systempakker. Kontroller netværksforbindelsen."
    exit 1
}

# Installer nødvendige pakker, hvis de mangler
for pkg in python3-venv python3-pip curl dpkg; do
    if ! dpkg -l | grep -qw $pkg; then
        echo "Installerer $pkg..."
        apt install -y $pkg || {
            echo "Fejl: Kunne ikke installere $pkg."
            exit 1
        }
    fi
done

# Installer nødvendige systempakker
echo "Installerer nødvendige pakker..."
apt install -y python3 portaudio19-dev libasound2-dev ffmpeg || {
    echo "Fejl ved installation af systempakker."
    exit 1
}

# Download og installer Ollama til CPU-brug
echo "Installerer Ollama..."
curl -fsSL https://ollama.com/install.sh | sh || {
    echo "Fejl: Ollama installation mislykkedes."
    exit 1
}

# Tjekker, om Ollama er installeret korrekt
if ! command -v ollama &> /dev/null; then
    echo "Ollama blev ikke installeret korrekt."
    exit 1
fi

# Installer Piper til offline TTS
echo "Installerer Piper til dansk TTS..."
apt install -y piper || {
    echo "Fejl ved installation af Piper."
    exit 1
}

# Tjekker, om Piper er installeret korrekt
if ! command -v piper &> /dev/null; then
    echo "Piper blev ikke installeret korrekt."
    exit 1
fi

# Opret en Python-virtual environment
echo "Opretter Python-virtual environment for IGOR..."
python3 -m venv igor_env || { echo "Kunne ikke oprette Python-venv."; exit 1; }

# Aktiverer virtuelt miljø og opdaterer pip
echo "Aktiverer Python-venv og opdaterer pip..."
source igor_env/bin/activate
pip install --upgrade pip || { echo "Fejl ved opdatering af pip."; deactivate; exit 1; }

# Opret requirements.txt for Python-afhængigheder uden playsound
cat << 'EOF' > requirements.txt
openai-whisper
SpeechRecognition
pyaudio
requests
beautifulsoup4
EOF

# Installerer Python-afhængigheder individuelt
echo "Installerer Python-afhængigheder..."
for package in $(cat requirements.txt); do
    echo "Installerer $package..."
    pip install $package || {
        echo "Fejl ved installation af $package."
        deactivate
        exit 1
    }
done

# Installer pygame som alternativ til playsound
echo "Installerer pygame til lydafspilning..."
pip install pygame || {
    echo "Fejl ved installation af pygame. Lydafspilning vil ikke være tilgængelig."
}

# Tjekker, om alle Python-afhængigheder blev installeret korrekt
for package in openai-whisper SpeechRecognition pyaudio requests beautifulsoup4 pygame; do
    if ! python3 -c "import $package" &> /dev/null; then
        echo "$package blev ikke installeret korrekt."
        deactivate
        exit 1
    fi
done

# Opret igor.py med Ollama LLM-integration, Piper TTS og Whisper stemmegenkendelse
echo "Opretter igor.py med Ollama LLM-integration, Piper TTS og Whisper stemmegenkendelse..."
cat << 'EOF' > igor.py
import subprocess
import os
import random
import speech_recognition as sr
import requests
from bs4 import BeautifulSoup
import pygame
import whisper

# Initialiser Whisper model
recognizer = sr.Recognizer()
whisper_model = whisper.load_model("base")

def random_response(responses):
    return random.choice(responses)

def igor_intro():
    print("IGOR: Hej, min herre! Jeg er IGOR, din ydmyge assistent og robotven. Lad mig vide, hvad jeg kan gøre for dig!")
    igor_talk("Hej, min herre! Jeg er IGOR, din ydmyge assistent og robotven. Lad mig vide, hvad jeg kan gøre for dig!")

def igor_talk(text):
    print("IGOR: " + text)
    try:
        subprocess.run(["piper", "--voice", "da-DK", "--text", text, "--output_file", "igor_response.wav"])
        pygame.mixer.init()
        pygame.mixer.music.load("igor_response.wav")
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            continue
        os.remove("igor_response.wav")
        pygame.mixer.quit()
    except Exception as e:
        print("Fejl ved TTS med Piper:", e)

def listen():
    with sr.Microphone() as source:
        igor_talk("Jeg lytter opmærksomt...")
        audio = recognizer.listen(source)
        with open("command.wav", "wb") as f:
            f.write(audio.get_wav_data())
        result = whisper_model.transcribe("command.wav", language="da")
        command = result["text"].strip()
        os.remove("command.wav")
        print("Du sagde: " + command)
        return command.lower()

def internet_search(query):
    url = f"https://duckduckgo.com/html/?q={query}"
    try:
        response = requests.get(url)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        results = soup.find_all('a', class_='result__a', limit=3)
        if results:
            search_results = "Her er, hvad jeg fandt på internettet for dig:\n"
            for result in results:
                search_results += f"- {result.get_text()}: {result['href']}\n"
            igor_talk(search_results)
        else:
            igor_talk("Desværre, min herre, ingen resultater denne gang!")
    except Exception as e:
        print("Fejl ved internetsøgning:", e)
        igor_talk("Ak og ve, noget gik galt under søgningen. Måske har internettet en dårlig dag?")

def generate_response(prompt):
    try:
        result = subprocess.run(["ollama", "generate", "tiny", prompt], capture_output=True, text=True)
        response = result.stdout.strip()
        return response if response else random_response(["Jeg kunne ikke finde et svar.", "Beklager, men der gik noget galt."])
    except Exception as e:
        print("Fejl ved Ollama LLM:", e)
        return random_response(["Jeg kan ikke svare lige nu.", "Noget gik galt i min hjerne!"])

igor_intro()

while True:
    command = listen()
    if command:
        if "farvel" in command:
            igor_talk(random_response(["Farvel, min herre.", "Vi ses snart igen!"]))
            break
        elif "søg efter" in command:
            query = command.replace("søg efter", "").strip()
            internet_search(query)
        else:
            response = generate_response(command)
            igor_talk(response)
EOF

chmod +x igor.py

echo "Installationen er fuldført. For at starte IGOR, aktiver venligst Python-venv og kør igor.py:"
echo "source igor_env/bin/activate && python igor.py"
