---
title: Certificates
---
# Self-Signed Certificates for Hosting Swift Paperless

It has been verified that self-signed certificates work with **Swift Paperless** when properly configured. However, the certificate **must be imported into the iOS trust store** for it to be recognized. To verify that everything is set up correctly, **Safari should be able to connect to the server without displaying a certificate warning**.

This guide explains how to create a self-signed certificate for hosting the **Paperless-ngx** backend securely. **Swift Paperless** is a native iOS client that connects to **Paperless-ngx**, a self-hosted document management system. This process ensures encrypted communication between Swift Paperless and the Paperless-ngx backend. It also covers mutual TLS (mTLS) for additional authentication security.

## **Prerequisites**
- OpenSSL installed on the system
- A server where **Paperless-ngx** is hosted

!!! tip "Important Notes"
      - Apple platforms require the `-legacy` flag when exporting certificates to `.p12` format.
      - Certificates **cannot** have a lifetime longer than **365 days**, or they will be rejected.
      - A **separate CA certificate** is required, distinct from the server certificate.
      - The **subjectAltName (SAN)** extension must be included in certificates for modern browsers and operating systems to recognize them as valid.

---

## **1. Creating a Certificate Authority (CA)**

A Certificate Authority (CA) is required to sign the server certificate. This ensures proper certificate validation.

!!! question "Why is a separate CA certificate needed?"
      Having a CA certificate distinct from the server certificate allows multiple server and client certificates to be issued while maintaining trust across the system. Aside from this, empirically, the iOS network stack appears to reject connections where the server responds directly with a CA certificate.

```bash
openssl req \
  -newkey rsa:4096 \
  -x509 \
  -keyout ca.key \
  -out ca.crt \
  -days 365 \
  -nodes \
  -subj "/CN=MyCA"
```

This command generates:

- `ca.key`: Private key for the CA
- `ca.crt`: Public CA certificate used to sign server certificates

---

## **2. Creating a Self-Signed Server Certificate**
The server certificate must be signed by the CA, ensuring secure communication between the client and server.

### **What is subjectAltName (SAN)?**
The **subjectAltName (SAN)** field is an extension to X.509 certificates that allows specifying additional hostnames, IP addresses, or domain names for which the certificate is valid. Most modern browsers and applications require SAN to be present, as the `CN` (Common Name) field alone is no longer considered sufficient for validation.

### **Generate a certificate signing request (CSR) with subjectAltName**
```bash
openssl req \
  -newkey rsa:4096 \
  -keyout server.key \
  -out server.csr \
  -nodes \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

### **Sign the certificate with the CA**
```bash
openssl x509 \
  -req \
  -in server.csr \
  -out server.crt \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -days 365 \
  -copy_extensions copyall
```

This produces:

- `server.key`: Private key for the *Paperless-ngx* backend server
- `server.crt`: The signed server certificate

---

## **3. Checking Certificate Validity**
To confirm the certificate’s expiration date:
```bash
openssl x509 -enddate -noout -in server.crt
```
Ensure that the certificate does **not exceed 365 days**.

---

## **4. Client Certificates & Mutual TLS (mTLS)**

### **What is mTLS?**
Mutual TLS (mTLS) is a security feature that ensures both the client and server authenticate each other. Unlike standard TLS, where only the server proves its identity, mTLS adds a layer of trust by requiring the client to present a valid certificate as well.

This is useful for:
- Securing communication between **Swift Paperless** and the **Paperless-ngx** backend
- Restricting access to only authorized clients

For more information on mTLS, see [Cloudflare's mTLS documentation](https://www.cloudflare.com/learning/access-management/what-is-mutual-tls/).

### **Generating a Client Certificate**

#### **Step 1: Generate the client certificate request**
```bash
openssl req \
  -newkey rsa:4096 \
  -keyout client.key \
  -out client.csr \
  -nodes \
  -subj "/CN=client"
```

#### **Step 2: Sign the client certificate with the CA**
```bash
openssl x509 \
  -req \
  -in client.csr \
  -out client.crt \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -days 365
```

This produces:

- `client.key`: Private key for the client
- `client.crt`: Signed client certificate

---

## **5. Converting the Client Certificate for Apple Platforms**
Apple platforms require certificates in `.p12` format for secure storage and use. Use the following command with the `-legacy` flag:

```bash
openssl pkcs12 \
  -export \
  -out client.p12 \
  -inkey client.key \
  -in client.crt \
  -legacy
```

!!! question "Why is `-legacy` required?"
      Without this flag, iOS and macOS may reject the certificate, causing authentication failures.

---

## **6. Testing mTLS with cURL**
To verify mTLS authentication:
```bash
curl -L https://localhost:8443 --cert client.crt --key client.key
```
If configured correctly, the server should accept the connection.

---

## **7. Summary**
- A **separate CA certificate** was created to sign other certificates.
- A **server certificate** was generated and signed to enable HTTPS for **Paperless-ngx**.
- **subjectAltName (SAN)** was included to ensure compatibility with modern browsers.
- **mTLS** was explained, and a **client certificate** was created for authentication.
- The client certificate was converted to **`.p12` format** for Apple compatibility.
- The setup was verified by ensuring **Safari connects without certificate warnings**.
- For further details on mTLS, refer to [Cloudflare's mTLS documentation](https://www.cloudflare.com/learning/access-management/what-is-mutual-tls/).

By following these steps, **Swift Paperless** can securely communicate with a self-hosted **Paperless-ngx** instance using strong encryption and authentication. 🚀
