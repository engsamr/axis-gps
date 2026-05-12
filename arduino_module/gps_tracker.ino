// Define modem type
#define TINY_GSM_MODEM_SIM7600

// Serial monitor
#define SerialMon Serial

// Serial connection to SIM7600
#define SerialAT Serial1

#include <TinyGsmClient.h>
#include <PubSubClient.h>

// ESP32 pins
#define MODEM_RX 26
#define MODEM_TX 27
#define MODEM_PWRKEY 4
#define MODEM_POWER_ON 12

// APN
const char apn[] = "internet";

// MQTT settings
const char* broker = "broker.hivemq.com";
const int mqttPort = 1883;
const char* topic = "qatar/gps/tracker1";

// Create modem objects
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
PubSubClient mqtt(gsmClient);

// -------- GEO-FENCE BLOCK --------
float minLat = 25.368000;
float maxLat = 25.382000;

float minLon = 51.480000;
float maxLon = 51.497000;

bool alertSent = false;



// -------- ALERT FUNCTION --------
void sendAlert(String message) {

  modem.sendAT("+CMGF=1");   // alert text mode
  modem.waitResponse();

  modem.sendAT("+CMGS=\"+97470006058\""); // replace with your number
  modem.waitResponse(">");

  SerialAT.print(message);
  SerialAT.write(26); // CTRL+Z

  modem.waitResponse(10000L);

  SerialMon.println("Alert Sent");
}


void setup() {

  SerialMon.begin(115200);
  delay(3000);

  // Power modem
  pinMode(MODEM_POWER_ON, OUTPUT);
  digitalWrite(MODEM_POWER_ON, HIGH);

  // Start modem
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(6000);

  // Serial communication
  SerialAT.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(3000);

  modem.restart();

  SerialMon.println("Waiting for network...");

  if (!modem.waitForNetwork(60000)) {
    SerialMon.println("Network FAILED");
    while (true);
  }

  // Connect to internet
  if (!modem.gprsConnect(apn, "", "")) {
    SerialMon.println("GPRS FAILED");
    while (true);
  }

  SerialMon.println("Internet Connected");

  // Enable GPS
  modem.sendAT("+CGPS=0");
  modem.waitResponse(3000);

  modem.sendAT("+CGPS=1,1");
  modem.waitResponse(10000L);

  // MQTT setup
  mqtt.setServer(broker, mqttPort);

  SerialMon.println("Tracker Ready");
}


void loop() {

  float lat, lon;

  // MQTT reconnect
  if (!mqtt.connected()) {
    mqtt.connect("TrackerClient1");
  }

  // Get GPS
  if (modem.getGPS(&lat, &lon)) {

    String gpsData = String(lat, 6) + "," + String(lon, 6);

    mqtt.publish(topic, gpsData.c_str());

    SerialMon.println("GPS Sent: " + gpsData);

    // -------- GEOFENCE CHECK --------
    bool outside = (lat < minLat || lat > maxLat ||
                    lon < minLon || lon > maxLon);
    if (outside) {
    SerialMon.println("Outside geofence!");
    } else {
    SerialMon.println("Inside geofence.");
    }

    if (outside && !alertSent) {

      String message = "ALERT! Vehicle left safe zone.\n";
      message += "Location:\n";
      message += "https://maps.google.com/?q=" +
                 String(lat,6) + "," + String(lon,6);

      sendAlert(message);

      alertSent = true;
    }

    if (!outside) {
      alertSent = false;
    }

  } else {

    SerialMon.println("Waiting for GPS fix...");

  }

  delay(5000);
}
