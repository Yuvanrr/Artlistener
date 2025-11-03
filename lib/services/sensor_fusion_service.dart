import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart' as vec;
import 'package:permission_handler/permission_handler.dart';

/// Advanced Inertial Sensor Fusion Service
/// Combines accelerometer, gyroscope, and magnetometer data
/// for improved indoor positioning accuracy
class SensorFusionService {
  // Sensor streams
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  // Sensor data buffers for Kalman filtering
  final List<vec.Vector3> _accelerometerData = [];
  final List<vec.Vector3> _gyroscopeData = [];
  final List<vec.Vector3> _magnetometerData = [];

  // Kalman filter state
  vec.Vector3 _position = vec.Vector3.zero();
  vec.Vector3 _velocity = vec.Vector3.zero();
  vec.Vector3 _orientation = vec.Vector3.zero();

  // Kalman filter matrices
  vec.Matrix3 _positionCovariance = vec.Matrix3.identity() * 0.1;
  vec.Matrix3 _velocityCovariance = vec.Matrix3.identity() * 0.1;

  // Noise parameters (tuned for indoor use)
  static const double _processNoise = 0.01;
  static const double _measurementNoise = 0.1;
  static const double _sampleRate = 50.0; // Hz

  // Complementary filter alpha (for orientation)
  static const double _alpha = 0.98;

  bool _isInitialized = false;
  bool _isCalibrated = false;

  // Calibration data
  vec.Vector3 _accelerometerBias = vec.Vector3.zero();
  vec.Vector3 _gyroscopeBias = vec.Vector3.zero();
  vec.Vector3 _magnetometerBias = vec.Vector3.zero();

  /// Initialize sensor fusion with permissions
  Future<bool> initialize() async {
    try {
      // Request sensor permissions
      final status = await Permission.sensors.request();
      if (status.isDenied) {
        print('❌ Sensor permissions denied');
        return false;
      }

      print('🔄 Initializing sensor fusion...');
      await _calibrateSensors();

      _startSensorStreams();
      _isInitialized = true;

      print('✅ Sensor fusion initialized successfully');
      return true;
    } catch (e) {
      print('❌ Failed to initialize sensor fusion: $e');
      return false;
    }
  }

  /// Calibrate sensors to remove bias
  Future<void> _calibrateSensors() async {
    print('📐 Calibrating sensors...');

    const int calibrationSamples = 100;
    final List<vec.Vector3> accelSamples = [];
    final List<vec.Vector3> gyroSamples = [];
    final List<vec.Vector3> magSamples = [];

    // Collect samples
    await for (final event in accelerometerEvents.take(calibrationSamples)) {
      accelSamples.add(vec.Vector3(event.x, event.y, event.z));
    }

    await for (final event in gyroscopeEvents.take(calibrationSamples)) {
      gyroSamples.add(vec.Vector3(event.x, event.y, event.z));
    }

    await for (final event in magnetometerEvents.take(calibrationSamples)) {
      magSamples.add(vec.Vector3(event.x, event.y, event.z));
    }

    // Calculate bias (average offset)
    if (accelSamples.isNotEmpty) {
      _accelerometerBias = _calculateAverageVector(accelSamples);
      // Remove gravity component (should be ~9.81 m/s² in Z direction)
      _accelerometerBias.z -= 9.81;
    }

    if (gyroSamples.isNotEmpty) {
      _gyroscopeBias = _calculateAverageVector(gyroSamples);
    }

    if (magSamples.isNotEmpty) {
      _magnetometerBias = _calculateAverageVector(magSamples);
    }

    _isCalibrated = true;
    print('✅ Sensor calibration complete');
    print('   Accelerometer bias: ${_accelerometerBias.toString()}');
    print('   Gyroscope bias: ${_gyroscopeBias.toString()}');
    print('   Magnetometer bias: ${_magnetometerBias.toString()}');
  }

  vec.Vector3 _calculateAverageVector(List<vec.Vector3> vectors) {
    if (vectors.isEmpty) return vec.Vector3.zero();

    double sumX = 0, sumY = 0, sumZ = 0;
    for (final vector in vectors) {
      sumX += vector.x;
      sumY += vector.y;
      sumZ += vector.z;
    }

    return vec.Vector3(
      sumX / vectors.length,
      sumY / vectors.length,
      sumZ / vectors.length,
    );
  }

  /// Start collecting sensor data streams
  void _startSensorStreams() {
    print('📡 Starting sensor data streams...');

    // Accelerometer (linear acceleration)
    _accelerometerSubscription = accelerometerEvents.listen(
      (event) {
        final corrected = vec.Vector3(event.x, event.y, event.z) - _accelerometerBias;
        _accelerometerData.add(corrected);

        // Keep buffer size manageable
        if (_accelerometerData.length > 100) {
          _accelerometerData.removeAt(0);
        }

        _updateKalmanFilter(corrected, SensorType.accelerometer);
      },
      onError: (error) => print('❌ Accelerometer error: $error'),
    );

    // Gyroscope (angular velocity)
    _gyroscopeSubscription = gyroscopeEvents.listen(
      (event) {
        final corrected = vec.Vector3(event.x, event.y, event.z) - _gyroscopeBias;
        _gyroscopeData.add(corrected);

        if (_gyroscopeData.length > 100) {
          _gyroscopeData.removeAt(0);
        }

        _updateOrientation(corrected);
      },
      onError: (error) => print('❌ Gyroscope error: $error'),
    );

    // Magnetometer (magnetic field)
    _magnetometerSubscription = magnetometerEvents.listen(
      (event) {
        final corrected = vec.Vector3(event.x, event.y, event.z) - _magnetometerBias;
        _magnetometerData.add(corrected);

        if (_magnetometerData.length > 100) {
          _magnetometerData.removeAt(0);
        }

        _updateOrientationWithMagnetometer(corrected);
      },
      onError: (error) => print('❌ Magnetometer error: $error'),
    );
  }

  /// Update Kalman filter with new measurement
  void _updateKalmanFilter(vec.Vector3 measurement, SensorType type) {
    if (!_isCalibrated) return;

    final dt = 1.0 / _sampleRate;

    // Prediction step
    _position += _velocity * dt;
    _velocity += measurement * dt;

    // Add process noise
    _positionCovariance += vec.Matrix3.identity() * _processNoise * dt;
    _velocityCovariance += vec.Matrix3.identity() * _processNoise * dt;

    // Update step (simplified Kalman gain)
    final positionTrace = _positionCovariance.entry(0, 0) + _positionCovariance.entry(1, 1) + _positionCovariance.entry(2, 2);
    final kalmanGain = _measurementNoise / (_measurementNoise + positionTrace);

    // Apply measurement
    final innovation = measurement - _position;
    _position += innovation * kalmanGain;
    _velocity += (measurement - _velocity) * kalmanGain * 0.5;

    // Update covariance
    _positionCovariance *= (1.0 - kalmanGain);
    _velocityCovariance *= (1.0 - kalmanGain * 0.5);
  }

  /// Update orientation using complementary filter
  void _updateOrientation(vec.Vector3 gyroData) {
    if (!_isCalibrated) return;

    final dt = 1.0 / _sampleRate;

    // Integrate gyroscope data for orientation change
    _orientation += gyroData * dt;

    // Normalize angle to [-pi, pi]
    _orientation.x = _normalizeAngle(_orientation.x);
    _orientation.y = _normalizeAngle(_orientation.y);
    _orientation.z = _normalizeAngle(_orientation.z);
  }

  /// Update orientation using magnetometer for heading correction
  void _updateOrientationWithMagnetometer(vec.Vector3 magData) {
    if (!_isCalibrated || _magnetometerData.length < 10) return;

    // Calculate heading from magnetometer
    final heading = atan2(magData.y, magData.x);

    // Complementary filter: combine gyroscope and magnetometer
    _orientation.z = _alpha * (_orientation.z + _gyroscopeData.last.z / _sampleRate) +
                    (1.0 - _alpha) * heading;
  }

  double _normalizeAngle(double angle) {
    while (angle > pi) angle -= 2 * pi;
    while (angle < -pi) angle += 2 * pi;
    return angle;
  }

  /// Get current fused position estimate
  vec.Vector3 getCurrentPosition() => _position;

  /// Get current orientation (roll, pitch, yaw)
  vec.Vector3 getCurrentOrientation() => _orientation;

  /// Get movement confidence based on sensor data quality
  double getMovementConfidence() {
    if (!_isInitialized || !_isCalibrated) return 0.0;

    // Calculate confidence based on:
    // 1. Sensor data consistency
    // 2. Movement magnitude
    // 3. Covariance values

    double confidence = 0.5; // Base confidence

    // Check data consistency
    if (_accelerometerData.length > 10) {
      final variance = _calculateVariance(_accelerometerData);
      confidence += 0.2 * (1.0 - variance / 10.0); // Lower variance = higher confidence
    }

    // Check movement magnitude
    final movementMagnitude = _position.length;
    if (movementMagnitude > 0.1) {
      confidence += 0.2; // Movement detected
    }

    // Check covariance (lower covariance = higher confidence)
    final positionTrace = _positionCovariance.entry(0, 0) + _positionCovariance.entry(1, 1) + _positionCovariance.entry(2, 2);
    final velocityTrace = _velocityCovariance.entry(0, 0) + _velocityCovariance.entry(1, 1) + _velocityCovariance.entry(2, 2);
    final avgCovariance = (positionTrace + velocityTrace) / 6.0;
    confidence += 0.1 * (1.0 - avgCovariance / 0.1);

    return confidence.clamp(0.0, 1.0);
  }

  double _calculateVariance(List<vec.Vector3> vectors) {
    if (vectors.length < 2) return 0.0;

    final mean = _calculateAverageVector(vectors);
    double variance = 0.0;

    for (final vector in vectors) {
      final diff = (vector - mean).length;
      variance += diff * diff;
    }

    return variance / vectors.length;
  }

  /// Check if user is stationary (for WiFi fingerprint stability)
  bool isStationary({double threshold = 0.5}) {
    if (_accelerometerData.length < 10) return false;

    final recentData = _accelerometerData.take(10).toList();
    final variance = _calculateVariance(recentData);

    return variance < threshold;
  }

  /// Get sensor quality metrics
  Map<String, double> getSensorQuality() {
    return {
      'accelerometer_stability': _accelerometerData.isEmpty ? 0.0 : 1.0 - _calculateVariance(_accelerometerData) / 5.0,
      'gyroscope_stability': _gyroscopeData.isEmpty ? 0.0 : 1.0 - _calculateVariance(_gyroscopeData) / 1.0,
      'magnetometer_stability': _magnetometerData.isEmpty ? 0.0 : 1.0 - _calculateVariance(_magnetometerData) / 100.0,
      'movement_confidence': getMovementConfidence(),
      'calibration_status': _isCalibrated ? 1.0 : 0.0,
    };
  }

  /// Dispose of sensor streams
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();

    _accelerometerData.clear();
    _gyroscopeData.clear();
    _magnetometerData.clear();

    _isInitialized = false;
    _isCalibrated = false;
  }
}

enum SensorType {
  accelerometer,
  gyroscope,
  magnetometer,
}
