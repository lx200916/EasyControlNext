package com.shiyunjin.easycontrolnext.app.adb;

import android.os.Build;
import android.sun.security.x509.AlgorithmId;
import android.sun.security.x509.CertificateAlgorithmId;
import android.sun.security.x509.CertificateExtensions;
import android.sun.security.x509.CertificateIssuerName;
import android.sun.security.x509.CertificateSerialNumber;
import android.sun.security.x509.CertificateSubjectName;
import android.sun.security.x509.CertificateValidity;
import android.sun.security.x509.CertificateVersion;
import android.sun.security.x509.CertificateX509Key;
import android.sun.security.x509.KeyIdentifier;
import android.sun.security.x509.PrivateKeyUsageExtension;
import android.sun.security.x509.SubjectKeyIdentifierExtension;
import android.sun.security.x509.X500Name;
import android.sun.security.x509.X509CertImpl;
import android.sun.security.x509.X509CertInfo;

import androidx.annotation.NonNull;

import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.cert.Certificate;
import java.util.Date;
import java.util.Random;

import io.github.muntashirakon.adb.AbsAdbConnectionManager;

public class AdbConnectionManager extends AbsAdbConnectionManager {
    public static AbsAdbConnectionManager keyPairClient(AdbKeyPair keyPair) throws Exception {
        return new AdbConnectionManager(keyPair);
    }

    private final PrivateKey mPrivateKey;
    private final Certificate mCertificate;

    private AdbConnectionManager(AdbKeyPair keyPair) throws Exception {
        setApi(Build.VERSION.SDK_INT);
        mPrivateKey = keyPair.privateKey;
        PublicKey publicKey = keyPair.getPublicKey();
        // Generate a new certificate
        String subject = "CN=Easy Control Next";
        String algorithmName = "SHA512withRSA";
        long expiryDate = System.currentTimeMillis() + 1000L * 60L * 60L * 24L * 365L * 30L; // ~30 years
        CertificateExtensions certificateExtensions = new CertificateExtensions();
        certificateExtensions.set("SubjectKeyIdentifier", new SubjectKeyIdentifierExtension(
                new KeyIdentifier(publicKey).getIdentifier()));
        X500Name x500Name = new X500Name(subject);
        Date notBefore = new Date(System.currentTimeMillis() - 24L * 60L * 60L * 1000L);
        Date notAfter = new Date(expiryDate);
        certificateExtensions.set("PrivateKeyUsage", new PrivateKeyUsageExtension(notBefore, notAfter));
        CertificateValidity certificateValidity = new CertificateValidity(notBefore, notAfter);
        X509CertInfo x509CertInfo = new X509CertInfo();
        x509CertInfo.set("version", new CertificateVersion(2));
        x509CertInfo.set("serialNumber", new CertificateSerialNumber(new Random().nextInt() & Integer.MAX_VALUE));
        x509CertInfo.set("algorithmID", new CertificateAlgorithmId(AlgorithmId.get(algorithmName)));
        x509CertInfo.set("subject", new CertificateSubjectName(x500Name));
        x509CertInfo.set("key", new CertificateX509Key(publicKey));
        x509CertInfo.set("validity", certificateValidity);
        x509CertInfo.set("issuer", new CertificateIssuerName(x500Name));
        x509CertInfo.set("extensions", certificateExtensions);
        X509CertImpl x509CertImpl = new X509CertImpl(x509CertInfo);
        x509CertImpl.sign(mPrivateKey, algorithmName);
        mCertificate = x509CertImpl;
    }

    @NonNull
    @Override
    protected PrivateKey getPrivateKey() {
        return mPrivateKey;
    }

    @NonNull
    @Override
    protected Certificate getCertificate() {
        return mCertificate;
    }

    @NonNull
    @Override
    protected String getDeviceName() {
        return "EasyControlNext";
    }
}