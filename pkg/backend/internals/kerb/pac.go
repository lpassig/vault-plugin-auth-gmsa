package kerb

// In a real implementation, verify:
//  - PAC_SIGNATURE_DATA: server and KDC signatures
//  - UPN_DNS_INFO consistency
//  - LOGON_INFO groups and SIDs
// Return parsed SIDs and principal canonical name.
//
// Keep this in a separate file so you can unit-test it with captured PAC blobs.
