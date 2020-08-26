/**
 * Copyright (c) Mobeye.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @format
 */
import MobeyeGeolocation from './nativeModule';
import { Location, LocationEvent } from './types';
import { NativeEventEmitter, PermissionStatus } from 'react-native';
import { useEffect, useState } from 'react';

/* get native module */
const { configuration, start, startBestAccuracyLocation, stopBestAccuracyLocation } = MobeyeGeolocation;

/**
 * Get last `n` last locations computed by the service.
 * @param n last computed locations
 */
export function getLastLocations(n: number): Promise<[Location]> {
    return MobeyeGeolocation.getLastLocations(n).then((result) => {
        const locations: [Location] = JSON.parse(result);
        return locations;
    });
}

/**
 * Get last location computed by the service.
 */
export function getLastLocation(): Promise<Location> {
    return getLastLocations(1).then((res) => res[0]);
}

/**
 * Check location authorization for iOS.
 * To check for android just use AndroidPermissions
 */
export function checkIOSAuthorization(): Promise<boolean> {
    return MobeyeGeolocation.checkPermission();
}

/**
 * Request location authorization for iOS.
 * To request for android just use AndroidPermissions
 */
export function requestIOSAuthorization(): Promise<PermissionStatus> {
    return MobeyeGeolocation.askForPermission();
}

/* Native event emitter to catch geolocations event */
export const locationEmitter = new NativeEventEmitter(MobeyeGeolocation);

/**
 * A React Hook which updates when the location significantly changes.
 */
export function useLocation(): Location {

    const [location, setLocation] = useState<Location>({
        latitude: -1,
        longitude: -1,
        accuracy: Number.MAX_SAFE_INTEGER,
        time: 0,
    });

    useEffect(() => {
        /* get last known use position */
        getLastLocation().then((res) => setLocation(res));

        /* subscribe to the listener */
        const subscription = locationEmitter.addListener('LOCATION_UPDATED', (result: LocationEvent) => {
            if (result.success) {
                setLocation(result.payload);
            }
        });
        return () => subscription.remove();
    }, []);

    return location;
}

export default {
    configuration,
    start,
    startBestAccuracyLocation,
    stopBestAccuracyLocation,
    getLastLocation,
    getLastLocations,
    checkIOSAuthorization,
    requestIOSAuthorization,
};
