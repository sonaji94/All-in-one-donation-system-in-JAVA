package com.donation.platform;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

@SpringBootApplication
@EnableRetry
@EnableAsync
public class DonationPlatformApplication {

    public static void main(String[] args) {
        SpringApplication.run(DonationPlatformApplication.class, args);
    }
}
