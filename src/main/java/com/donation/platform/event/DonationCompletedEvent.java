package com.donation.platform.event;

import com.donation.platform.entity.Donation;
import lombok.Getter;
import org.springframework.context.ApplicationEvent;

import java.util.UUID;

@Getter
public class DonationCompletedEvent extends ApplicationEvent {

    private final UUID donationId;
    private final Donation donation;

    public DonationCompletedEvent(Object source, Donation donation) {
        super(source);
        this.donation = donation;
        this.donationId = donation.getId();
    }
}
