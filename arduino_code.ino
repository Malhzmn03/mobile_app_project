#include <WiFi.h>
#include <ArduinoJson.h> 
#include <IOXhop_FirebaseESP32.h>
#include "DHT.h"

// =========================
// WIFI CONFIG
// =========================
const char* ssid = "Blackshadow2";
const char* password = "hamzahc7";

// =========================
// FIREBASE CONFIG
// =========================
#define FIREBASE_HOST "smart-home-5a793-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "0qwBv8Vgs2EgulCFfNNybJ5ifXcRE3HBRYDiyFzT"

// =========================
// DHT & Pins
// =========================
#define DHTPIN 15
#define DHTTYPE DHT11
#define LDR_DO 32
#define BUZZER 27
#define RELAY1 25
#define RELAY2 26
#define TRIG 12
#define ECHO 14

DHT dht(DHTPIN, DHTTYPE);

// Flags
bool isDark = false;
bool ultrasonicAlert = false;

// =========================
// SETUP
// =========================
void setup() {
  Serial.begin(115200);
  dht.begin();
  delay(2000);

  // Sambungan WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while(WiFi.status() != WL_CONNECTED){
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nConnected to WiFi");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // Sambungan Firebase
  Firebase.begin(FIREBASE_HOST, FIREBASE_AUTH);

  // Konfigurasi Pins
  pinMode(BUZZER, OUTPUT);
  pinMode(RELAY1, OUTPUT);
  pinMode(RELAY2, OUTPUT);
  pinMode(LDR_DO, INPUT);
  pinMode(TRIG, OUTPUT);
  pinMode(ECHO, INPUT);

  digitalWrite(RELAY1, HIGH);
  digitalWrite(RELAY2, HIGH);
}

// =========================
// LOOP
// =========================
void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi Disconnected.");
    delay(500);
    return;
  }

  // =========================
  // SENSOR READINGS
  // =========================
  float temp = dht.readTemperature();
  float hum = dht.readHumidity();
  int rawLdr = digitalRead(LDR_DO);

  // =========================
  // FORCE LOGIC:
  // 0 = CERAH
  // 1 = GELAP
  // =========================
  int ldr = (rawLdr == HIGH) ? 1 : 0;

  // Ultrasonic
  digitalWrite(TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG, LOW);
  long duration = pulseIn(ECHO, HIGH);
  float distance = duration * 0.034 / 2;

  // Debug print
  Serial.print("Temp: "); Serial.println(temp);
  Serial.print("Humidity: "); Serial.println(hum);
  Serial.print("LDR (0=cerah,1=gelap): "); Serial.println(ldr);
  Serial.print("Distance: "); Serial.println(distance);

  // =========================
  // BACA MANUAL CONTROL & MODE
  // =========================
  int relay1Mode = Firebase.getInt("/Mode/relay1");  // 0 = auto, 1 = manual
  int relay2Mode = Firebase.getInt("/Mode/relay2");
  int relay1Cmd = Firebase.getInt("/RelayControl/relay1");
  int relay2Cmd = Firebase.getInt("/RelayControl/relay2");

  // =========================
  // RELAY 1 CONTROL
  // =========================
  if (relay1Mode == 1) {
    // MANUAL MODE
    digitalWrite(RELAY1, relay1Cmd == 1 ? LOW : HIGH);
  } 
  else {
    // AUTO MODE (suhu) - Changed from 32°C to 24°C
    if (temp >= 24) digitalWrite(RELAY1, LOW);
    else digitalWrite(RELAY1, HIGH);
  }

  // =========================
  // RELAY 2 CONTROL (LDR)
  // =========================
  if (relay2Mode == 1) {
    // MANUAL MODE
    digitalWrite(RELAY2, relay2Cmd == 1 ? LOW : HIGH);
  } 
  else {
    // AUTO MODE (0=cerah, 1=gelap)
    if (ldr == 1) { // GELAP → Relay ON
      digitalWrite(RELAY2, LOW);
      if (!isDark) {
        digitalWrite(BUZZER, HIGH); delay(200); digitalWrite(BUZZER, LOW);
        isDark = true;
      }
    } else { // CERAH → Relay OFF
      digitalWrite(RELAY2, HIGH);
      if (isDark) {
        digitalWrite(BUZZER, HIGH); delay(200); digitalWrite(BUZZER, LOW);
        isDark = false;
      }
    }
  }

  // =========================
  // ULTRASONIC ALERT
  // =========================
  if (distance > 0 && distance <= 10) {
    if (!ultrasonicAlert) {
      digitalWrite(BUZZER, HIGH); delay(1000); digitalWrite(BUZZER, LOW);
      ultrasonicAlert = true;
    }
  } 
  else {
    ultrasonicAlert = false;
  }

  // =========================
  // PUSH SENSOR DATA
  // =========================
  Firebase.setFloat("/Sensors/Temperature", temp);
  Firebase.setFloat("/Sensors/Humidity", hum);
  Firebase.setInt("/Sensors/LDR", ldr);
  Firebase.setFloat("/Sensors/Distance", distance);

  // =========================
  // PUSH RELAY STATUS
  // =========================
  Firebase.setInt("/RelayStatus/relay1", digitalRead(RELAY1) == LOW ? 1 : 0);
  Firebase.setInt("/RelayStatus/relay2", digitalRead(RELAY2) == LOW ? 1 : 0);

  delay(1000);
}

