#include <SoftwareSerial.h>

// Pin Definitions
#define GAS_SENSOR_PIN A0
#define BUZZER_PIN 8
#define RED_LED_PIN 7
#define GREEN_LED_PIN 6

// Set up Bluetooth: Pin 10 receives (RX), Pin 11 transmits (TX)
SoftwareSerial BTSerial(10, 11); 

// Your custom threshold
#define THRESHOLD 250 

void setup() {
    Serial.begin(9600);      // Starts the USB connection for computer debugging
    BTSerial.begin(9600);    // Starts the Bluetooth connection for the phone
    
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(RED_LED_PIN, OUTPUT);
    pinMode(GREEN_LED_PIN, OUTPUT);
    
    Serial.println("System Active. Monitoring...");
    
    // Send a welcome message to the phone when it connects
    BTSerial.println("--- Gas Monitor Connected ---");
}

void loop() {
    int currentGasLevel = analogRead(GAS_SENSOR_PIN);
    
    // Print to your computer screen
    Serial.print("Local Gas Level: ");
    Serial.println(currentGasLevel);
    
    // Construct the data payload to send to your phone
    BTSerial.print("Gas: ");
    BTSerial.print(currentGasLevel);
    
    // Core Logic
    if (currentGasLevel > THRESHOLD) {
        // DANGER STATE
        digitalWrite(GREEN_LED_PIN, LOW);
        digitalWrite(RED_LED_PIN, HIGH);
        digitalWrite(BUZZER_PIN, HIGH);
        
        // Append the danger warning to the phone's payload
        BTSerial.println("  ||  STATUS: DANGER! ALARM!");
    } else {
        // SAFE STATE
        digitalWrite(RED_LED_PIN, LOW);
        digitalWrite(BUZZER_PIN, LOW);
        digitalWrite(GREEN_LED_PIN, HIGH);
        
        // Append the safe status to the phone's payload
        BTSerial.println("  ||  STATUS: Safe");
    }
    
    // A 1-second delay so the phone screen doesn't scroll too fast
    delay(1000); 
}