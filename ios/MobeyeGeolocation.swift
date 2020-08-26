//
//  MobeyeGeolocation.swift
//  MobeyeGeolocation
//
//  Created by Dimitri Desvillechabrol on 01/07/2020.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation
import CoreLocation


/**
 Location module using CoreLocation.
 */
@objc(MobeyeGeolocation)
class MobeyeGeolocation: RCTEventEmitter {
  private let locationManager = CLLocationManager()
  var resolver: RCTPromiseResolveBlock!
  var lastUsedLocation: MyLocation!
  var locationBuffer: RingBuffer<MyLocation>!
  var distanceFilter: CLLocationDistance!
  var desiredAccuracy: CLLocationAccuracy!
  var isBackground = false
  
  override static func requiresMainQueueSetup() -> Bool {
    return true
  }
  
  override func supportedEvents() -> [String]! {
    return ["LOCATION_UPDATED"]
  }

  /**
   /**
    Configure the location provider.
    
    - Parameters:
     - bufferSize: ring buffer size to stock previous location.
     - distance: minimum distance before an update event is generated.
     - accuracy: string in `LevelAccuracy`.
     - resolve: a promise that returns the result to the JS code
     - reject: return to the JS code if the promise is rejected.
    */
   */
  @objc
  func configuration(
    _ bufferSize: NSInteger,
    distanceFilter distance: NSInteger,
    accuracyLevel accuracy: NSString,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) -> Void {
    if let locationAccuracy = LocationAccuracyDict[accuracy as String] {
      
      /* save desired options */
      self.distanceFilter = CLLocationDistance(distance)
      self.desiredAccuracy = locationAccuracy
      
      /* set service options */
      self.locationManager.distanceFilter = self.distanceFilter
      self.locationManager.desiredAccuracy = self.desiredAccuracy
      self.locationManager.delegate = self
      
      /* create RingBuffer */
      self.locationBuffer = RingBuffer<MyLocation>(bufferSize)
      
      /* get stored data */
      let storedLocations = UserDefaults.standard.string(forKey: "location")
      let decoder = JSONDecoder()
      var jsonData: Data
      if (storedLocations != nil) {
        /* Initiate the ring buffer with stored locations */
        jsonData = storedLocations!.data(using: .utf8)!
        let locationsArray = try! decoder.decode([MyLocation].self, from: jsonData)
        self.locationBuffer = try! RingBuffer<MyLocation>(bufferSize, array: locationsArray)
      }
      let storedLastUsedLocation = UserDefaults.standard.string(forKey: "lastUsedLocation")
      if (storedLastUsedLocation != nil) {
        jsonData = storedLastUsedLocation!.data(using: .utf8)!
        self.lastUsedLocation = try! decoder.decode(MyLocation.self, from: jsonData)
      }
      
      /* listen life cycle */
      NotificationCenter.default.addObserver(self, selector:#selector(backgroundActivity(notification:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector:#selector(foregroundActivity(notification:)), name: UIApplication.willEnterForegroundNotification, object: nil)

      resolve(true)
    } else {
      let err = GeolocationError.BAD_ACCURACY_OPTION
      reject(err.info.code, err.info.description, nil)
    }
  }
  
  /**
   Start the location provider.
   */
  @objc
  func start() -> Void
  {
    self.locationManager.startUpdatingLocation()
    /* set background location updates */
    self.locationManager.pausesLocationUpdatesAutomatically = false
  }
  
  /**
   Get last locations computed by the provider.
   
   - Parameters:
    - number: `number` last computed locations.
    - resolve: promise that returns a list of locations to the JS code.
    - reject: return to the JS code if the promise is rejected.
   */
  @objc
  func getLastLocations(_ number: NSInteger,
                        resolver resolve: RCTPromiseResolveBlock,
                        rejecter reject: RCTPromiseRejectBlock) -> Void
  {
    var locationList: [MyLocation] = []
    var i = 0
    
    /* check if the provider is configured */
    if (self.locationBuffer == nil) {
      let err = GeolocationError.LOCATION_NOT_CONFIGURED
      reject(err.info.code, err.info.description, nil)
      return
    }
    
    /* fill the location list with last locations */
    for location in self.locationBuffer {
      if (i >= number) {
        break
      }
      locationList.append(location)
      i += 1
    }
    
    /* location list cannot be empty normaly */
    if (locationList.isEmpty) {
      let err = GeolocationError.LOCATION
      reject(err.info.code, err.info.description, nil)
      return
    }
    var stringDict: String!
    let data = try! JSONEncoder().encode(locationList)
    stringDict = String(data: data, encoding: String.Encoding.utf8) ?? ""
    resolve(stringDict)
  }
  
  /**
   Set provider options for best accuracy.
   Be careful those options will drain the battery.
   */
  @objc
  func startBestAccuracyLocation(_ distance: NSInteger) -> Void
  {
    self.locationManager.distanceFilter = CLLocationDistance(distance)
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
  }
  
  /*
   Set the service to balanced power and accuracy.
   */
  @objc
  func stopBestAccuracyLocation() -> Void
  {
    self.locationManager.distanceFilter = self.distanceFilter
    self.locationManager.desiredAccuracy = self.desiredAccuracy
  }
  
  /**
   Update the used location by React to provide the mission list.
   This variable is used to know if the user location has significantly changed.
   */
  func updateLastUsedLocation() -> Void
  {
    guard let lastLocation = self.locationBuffer.getLast() else {
      return
    }
    self.lastUsedLocation = lastLocation
    let data = try! JSONEncoder().encode(self.lastUsedLocation)
    let stringDict = String(data: data, encoding: .utf8) ?? ""
    UserDefaults.standard.set(stringDict, forKey: "lastUsedLocation")
  }
  
  @objc
  func checkPermission(_ resolve: RCTPromiseResolveBlock,
                       rejecter reject: RCTPromiseRejectBlock) -> Void
  {
    switch CLLocationManager.authorizationStatus() {
    case .authorizedWhenInUse, .authorizedAlways:
      resolve(true)
    default:
      resolve(false)
    }
  }
  
  @objc
  func askForPermission(_ resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: RCTPromiseRejectBlock) -> Void
  {
    /* check if the provider is configured */
    if (self.locationBuffer == nil) {
      let err = GeolocationError.LOCATION_NOT_CONFIGURED
      reject(err.info.code, err.info.description, nil)
      return
    }
    
    /* Request authorization */
    switch CLLocationManager.authorizationStatus() {
    case .notDetermined:
      self.resolver = resolve
      self.locationManager.requestAlwaysAuthorization()
      self.locationManager.delegate = self
      break
    case .denied, .restricted:
      resolve(PermissionStatus.NEVER_ASK_AGAIN)
      break
    case .authorizedAlways, .authorizedWhenInUse:
      resolve(PermissionStatus.GRANTED)
      break
    }
  }
  
  /**
   Method executed when the app start or go to foreground
   */
  @objc
  func foregroundActivity(notification: NSNotification) {
    self.setForegroundOptions()
    self.isBackground = false
  }
  
  /**
   Method executed when the app is in background
   */
  @objc
  func backgroundActivity(notification: NSNotification){
    self.writeBufferInStore()
    self.setBackgroundOptions()
    self.isBackground = true
  }
  
  /**
   Write the buffer in store as JSON format
   */
  func writeBufferInStore() {
    let locationArray = Array(self.locationBuffer.getArray() ?? [])
    let data = try! JSONEncoder().encode(locationArray)
    let stringDict = String(data: data, encoding: .utf8) ?? ""
    UserDefaults.standard.set(stringDict, forKey: "location")
  }
  
  /**
   Set provider options in foreground.
   */
  private func setForegroundOptions() {
    /* More accuracy and more update are wanted when the app is in foreground */
    self.locationManager.stopMonitoringSignificantLocationChanges()
    self.locationManager.startUpdatingLocation()
  }
  
  /**
   Set provider options in background.
   */
  private func setBackgroundOptions() {
    /* Use significant location change in background to reduce battery consumption */
    self.locationManager.stopUpdatingLocation()
    if CLLocationManager.authorizationStatus() != .authorizedAlways {
      return
    }
    if !CLLocationManager.significantLocationChangeMonitoringAvailable() {
      return
    }
    self.locationManager.startMonitoringSignificantLocationChanges()
  }
}

extension MobeyeGeolocation: CLLocationManagerDelegate {
  
  /**
   Callback if authorisations have changed.
   */
  func locationManager(_ manager: CLLocationManager,
                       didChangeAuthorization status: CLAuthorizationStatus) {
    switch status {
    case .restricted, .denied, .notDetermined:
      /* resolver needed only for the first time permission asking */
      if self.resolver != nil {
        self.resolver(PermissionStatus.DENIED);
        self.resolver = nil
      }
      manager.stopUpdatingLocation()
      manager.stopMonitoringSignificantLocationChanges()
      break
    case .authorizedWhenInUse, .authorizedAlways:
      if self.resolver != nil {
        self.resolver(PermissionStatus.GRANTED)
        self.resolver = nil
      }
      manager.startUpdatingLocation()
      break
    @unknown default:
      break
    }
  }
  
  /**
   Callback that transforms detected locations objects as String array and stores it in the buffer
   Emits an event if the user location changes significantly.
   */
  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {
    // check if the object is not empty
    guard let location = locations.last else {
      return
    }
    
    let result = MyLocation(location: location)
    locationBuffer.add(result)
    let locationDict = try? result.asDictionary()
   
    if (self.isBackground) {
      self.writeBufferInStore()
    }
    
    let dist = (self.lastUsedLocation?.distanceTo(latitude: result.latitude, longitude: result.longitude) ?? Double.greatestFiniteMagnitude)
    let significantChange = dist > 100.0
    if (significantChange) {
      self.updateLastUsedLocation()
      self.sendEvent(withName: "LOCATION_UPDATED", body: ["success": true, "payload": locationDict!])
    }
  }
  
  /**
   Callback if the location computing failed.
   */
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    self.sendEvent(withName: "LOCATION_UPDATED", body: ["success": false, "payload": error])
  }
}
