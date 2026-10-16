package com.donation.platform;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.retry.annotation.EnableRetry;

@SpringBootApplication
@EnableRetry
public class DonationPlatformApplication {

    public static void main(String[] args) {
        SpringApplication.run(DonationPlatformApplication.class, args);
    }
}
