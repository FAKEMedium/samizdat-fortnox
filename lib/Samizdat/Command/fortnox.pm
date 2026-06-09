package Samizdat::Command::fortnox;

use Mojo::Base 'Mojolicious::Command', -signatures;
use Mojo::Util qw(getopt encode decode trim);
use Data::Dumper;

# Ensure UTF-8 output
binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

has description => 'Sync customers and invoices with Fortnox';
has usage => sub ($self) { $self->extract_usage };

# Standard articles for Fortnox integration
has articles => sub {
  return [
    { ArticleNumber => '3010', Description => 'Domäner',       Type => 'SERVICE', VAT => 25, SalesAccount => 3010, EUVATAccount => 3110, ExportAccount => 3210, EUAccount => 3310 },
    { ArticleNumber => '3011', Description => 'Snapback',      Type => 'SERVICE', VAT => 25, SalesAccount => 3011, EUVATAccount => 3111, ExportAccount => 3211, EUAccount => 3311 },
    { ArticleNumber => '3012', Description => 'Webhosting',    Type => 'SERVICE', VAT => 25, SalesAccount => 3012, EUVATAccount => 3112, ExportAccount => 3212, EUAccount => 3312 },
    { ArticleNumber => '3013', Description => 'Konsultarbete', Type => 'SERVICE', VAT => 25, SalesAccount => 3013, EUVATAccount => 3113, ExportAccount => 3213, EUAccount => 3313 },
    { ArticleNumber => '3540', Description => 'Fakturaavgift', Type => 'SERVICE', VAT => 25, SalesAccount => 3540, EUVATAccount => 3540, ExportAccount => 3540, EUAccount => 3540 },
    { ArticleNumber => '3740', Description => 'Avrundning',    Type => 'SERVICE', VAT => 0,  SalesAccount => 3740, EUVATAccount => 3740, ExportAccount => 3740, EUAccount => 3740 },
  ];
};

# Standard accounts for Fortnox integration
has accounts => sub {
  return [
    { Number => '3010', Description => 'Domäner, svensk moms',       SRU => 7410, VATCode => 'MP1'  },
    { Number => '3011', Description => 'Snapback, svensk moms',      SRU => 7410, VATCode => 'MP1'  },
    { Number => '3012', Description => 'Webhosting, svensk moms',    SRU => 7410, VATCode => 'MP1'  },
    { Number => '3013', Description => 'Konsultarbete, svensk moms', SRU => 7410, VATCode => 'MP1'  },

    { Number => '3110', Description => 'Domäner EU, momsfri',        SRU => 7410, VATCode => 'FTEU' },
    { Number => '3111', Description => 'Snapback EU, momsfri',       SRU => 7410, VATCode => 'FTEU' },
    { Number => '3112', Description => 'Webhosting EU, momsfri',     SRU => 7410, VATCode => 'FTEU' },
    { Number => '3113', Description => 'Konsultarbete EU, momsfri',  SRU => 7410, VATCode => 'FTEU' },

    { Number => '3210', Description => 'Domäner export, momsfri',       SRU => 7410, VATCode => 'ÖTEU' },
    { Number => '3211', Description => 'Snapback export, momsfri',      SRU => 7410, VATCode => 'ÖTEU' },
    { Number => '3212', Description => 'Webhosting export, momsfri',    SRU => 7410, VATCode => 'ÖTEU' },
    { Number => '3213', Description => 'Konsultarbete export, momsfri', SRU => 7410, VATCode => 'ÖTEU' },

    { Number => '3310', Description => 'Domäner EU, svensk moms',       SRU => 7410, VATCode => 'MP1'  },
    { Number => '3311', Description => 'Snapback EU, svensk moms',      SRU => 7410, VATCode => 'MP1'  },
    { Number => '3312', Description => 'Webhosting EU, svensk moms',    SRU => 7410, VATCode => 'MP1'  },
    { Number => '3313', Description => 'Konsultarbete EU, svensk moms', SRU => 7410, VATCode => 'MP1'  },

    { Number => '3540', Description => 'Fakturaavgifter',               SRU => 7410, VATCode => 'MP1'  },

    { Number => '3740', Description => 'Öresavrundning',                  SRU => 7410, VATCode => ''     },
  ];
};

sub run ($self, @args) {
  getopt \@args,
    'prompt'       => \my $prompt,
    'customerid=s' => \my $customerid,
    'invoiceid=s'  => \my $invoiceid,
    'articleid=s'  => \my $articleid,
    'from=s'       => \my $from,
    'to=s'         => \my $to,
    'pdfonly'      => \my $pdfonly,
    'force'        => \my $force,
    'dry-run'      => \my $dry_run,
    'all'          => \my $all,
    'number=s'     => \my $number,
    'h|help'       => \my $help;

  my $subcommand = shift @args // '';
  my $resource   = shift @args // '';

  # Show help
  if ($help || !$subcommand) {
    print $self->usage;
    return;
  }

  # Store options in a hash for passing around
  my $opts = {
    prompt     => $prompt,
    customerid => $customerid,
    invoiceid  => $invoiceid,
    articleid  => $articleid,
    from       => $from,
    to         => $to,
    pdfonly    => $pdfonly,
    force      => $force,
    dry_run    => $dry_run,
    all        => $all,
    number     => $number,
  };

  if ($subcommand eq 'update') {
    if ($resource eq 'customer') {
      $self->_update_customer($opts);
    } elsif ($resource eq 'invoice') {
      $self->_update_invoice($opts);
    } elsif ($resource eq 'accounts') {
      $self->_update_accounts($opts);
    } elsif ($resource eq 'article') {
      $self->_update_article($opts);
    } else {
      say "Unknown resource: $resource";
      say "Valid resources: customer, invoice, accounts, article";
      return;
    }
  } elsif ($subcommand eq 'create') {
    if ($resource eq 'accounts') {
      $self->_create_accounts($opts);
    } else {
      say "Unknown resource: $resource";
      say "Valid resources: accounts";
      return;
    }
  } else {
    say "Unknown subcommand: $subcommand";
    say "Valid subcommands: update, create";
    return;
  }
}


sub _update_customer ($self, $opts) {
  my $fortnox  = $self->app->fortnox;
  my $customer = $self->app->customer;

  # Build ID list to process
  my @ids;
  if ($opts->{customerid}) {
    @ids = ($opts->{customerid});
  } elsif ($opts->{from}) {
    my $from_id = $opts->{from};
    my $to_id   = $opts->{to} // $from_id;
    @ids = ($from_id .. $to_id);
  } else {
    say "Error: Must specify --customerid or --from";
    return;
  }

  # Get existing Fortnox customers for comparison
  say "Fetching Fortnox customer list...";
  my %fortnox_customers;
  my $page = 1;
  while (my $result = $fortnox->getCustomer(0, { qp => { page => $page, limit => 500 } })) {
    last if (ref($result) ne 'HASH' || !exists($result->{Customers}));
    for my $fc (@{ $result->{Customers} }) {
      $fortnox_customers{ $fc->{CustomerNumber} } = $fc;
    }
    $page++;
  }
  say "Found " . scalar(keys %fortnox_customers) . " customers in Fortnox";

  my $eucountries = join('|', $customer->eucountries);
  my $processed = 0;
  my $skipped   = 0;

  for my $id (@ids) {
    # Get local customer
    my $customers = $customer->get({ where => { customerid => $id } });
    unless ($customers && @$customers) {
      say "Customer $id not found locally, skipping";
      $skipped++;
      next;
    }
    my $local = $customers->[0];

    # Build Fortnox customer data
    my $name = trim(sprintf('%s %s', $local->{firstname} // '', $local->{lastname} // ''));
    $name = trim($local->{company}) if ($local->{company} && $local->{company} ne '');
    my ($address1, $address2) = split /[\r\n]+/, ($local->{address} // '');

    # Determine entity type
    my $type = "PRIVATE";
    my $country = $local->{country} // '';

    if ($country eq 'SE') {
      # Swedish customers: analyze orgno to determine type
      # Swedish personal numbers have month (digit 3-4) in range 01-12
      # Swedish organization numbers have digit 3-4 >= 20
      if (length($local->{orgno} // '') > 3) {
        if (substr($local->{orgno}, 2, 2) >= 20) {
          # Organization number (20-99 in position 3-4)
          $type = "COMPANY";
        } elsif (($local->{vatno} && $local->{vatno} ne '') || ($local->{company} && $local->{company} ne '')) {
          # Personal number but has VAT number or company name (sole proprietor / enskild firma)
          $type = "COMPANY";
        }
      }
    } else {
      # Other countries: check if organization/company field or VAT number is set
      if (($local->{company} && $local->{company} ne '') || ($local->{vatno} && $local->{vatno} ne '')) {
        $type = "COMPANY";
      }
    }

    my $data = {
      Customer => {
        CustomerNumber     => $id,
        Name               => $name,
        Address1           => trim($address1 // ''),
        Address2           => trim($address2 // ''),
        ZipCode            => trim($local->{zip} // ''),
        City               => trim($local->{city} // ''),
        CountryCode        => trim($local->{country} // ''),
        Phone1             => trim(($local->{phone1} && $local->{phone1} ne '') ? $local->{phone1} : ($local->{phone2} // '')),
        Phone2             => trim($local->{phone2} // ''),
        Email              => trim($local->{contactemail} // ''),
        EmailInvoice       => trim(($local->{billingemail} && $local->{billingemail} ne '')
                              ? (split(',', $local->{billingemail}))[0]
                              : ($local->{contactemail} // '')),
        OrganisationNumber => trim($local->{orgno} // ''),
        OurReference       => trim($local->{reference} // ''),
        VATNumber          => trim($local->{vatno} // ''),
        Comments           => trim($local->{freetext} // ''),
        Currency           => uc(trim($local->{currency} // 'SEK')),
        Active             => $local->{active} // 1,
        TermsOfPayment     => '30',
        Type               => $type,
        VATType            => $fortnox->vatTypeName($fortnox->vatType($local)),
        DefaultDeliveryTypes => {
          Order   => 'EMAIL',
          Invoice => ($local->{invoicetype} && $local->{invoicetype} eq 'snailmail') ? 'PRINT' : 'EMAIL',
          Offer   => 'EMAIL'
        },
      }
    };

    # Prompt mode: show comparison and only prompt if differences exist
    if ($opts->{prompt}) {
      if (exists $fortnox_customers{$id}) {
        # Fetch full customer details for comparison (list API has limited fields)
        my $full_result = $fortnox->getCustomer($id);
        my $remote = $full_result->{Customer} // $fortnox_customers{$id};

        # Compare fields (normalize for comparison)
        my @diffs;
        my $local_data = $data->{Customer};

        # Compare key fields
        push @diffs, ['Name', $local_data->{Name}, $remote->{Name}]
          if ($local_data->{Name} // '') ne ($remote->{Name} // '');
        push @diffs, ['Email', $local_data->{Email}, $remote->{Email}]
          if ($local_data->{Email} // '') ne ($remote->{Email} // '');
        push @diffs, ['EmailInvoice', $local_data->{EmailInvoice}, $remote->{EmailInvoice}]
          if ($local_data->{EmailInvoice} // '') ne ($remote->{EmailInvoice} // '');
        push @diffs, ['Address1', $local_data->{Address1}, $remote->{Address1}]
          if ($local_data->{Address1} // '') ne ($remote->{Address1} // '');
        push @diffs, ['ZipCode', $local_data->{ZipCode}, $remote->{ZipCode}]
          if ($local_data->{ZipCode} // '') ne ($remote->{ZipCode} // '');
        push @diffs, ['City', $local_data->{City}, $remote->{City}]
          if ($local_data->{City} // '') ne ($remote->{City} // '');
        push @diffs, ['Country', $local_data->{CountryCode}, $remote->{CountryCode}]
          if ($local_data->{CountryCode} // '') ne ($remote->{CountryCode} // '');
        push @diffs, ['Phone1', $local_data->{Phone1}, $remote->{Phone1}]
          if ($local_data->{Phone1} // '') ne ($remote->{Phone1} // '');
        push @diffs, ['VATNumber', $local_data->{VATNumber}, $remote->{VATNumber}]
          if ($local_data->{VATNumber} // '') ne ($remote->{VATNumber} // '');
        push @diffs, ['Currency', $local_data->{Currency}, $remote->{Currency}]
          if ($local_data->{Currency} // '') ne ($remote->{Currency} // '');
        push @diffs, ['Type', $local_data->{Type}, $remote->{Type}]
          if ($local_data->{Type} // '') ne ($remote->{Type} // '');
        push @diffs, ['VATType', $local_data->{VATType}, $remote->{VATType}]
          if ($local_data->{VATType} // '') ne ($remote->{VATType} // '');

        # Skip if no differences
        unless (@diffs) {
          say "Customer $id: $name - no changes";
          $skipped++;
          next;
        }

        say "\n" . "=" x 60;
        say "Customer $id: $name";
        say "=" x 60;
        say "\nDifferences (Local | Remote):";
        for my $diff (@diffs) {
          say sprintf("  %-20s: %-30s | %-30s", $diff->[0], $diff->[1] // '', $diff->[2] // '');
        }
        say "\nAction: UPDATE existing";
      } else {
        say "\n" . "=" x 60;
        say "Customer $id: $name";
        say "=" x 60;
        say "\nLocal data:";
        say sprintf("  %-20s: %s", "Name", $name);
        say sprintf("  %-20s: %s", "Email", $local->{contactemail} // '');
        say sprintf("  %-20s: %s", "City", $local->{city} // '');
        say sprintf("  %-20s: %s", "Country", $local->{country} // '');
        say sprintf("  %-20s: %s", "OrgNo", $local->{orgno} // '');
        say sprintf("  %-20s: %s", "Type", $type);
        say "\nAction: CREATE new";
      }

      print "\nProceed? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }
    }

    # Dry run
    if ($opts->{dry_run}) {
      my $action = exists($fortnox_customers{$id}) ? 'UPDATE' : 'CREATE';
      say "DRY RUN: Would $action customer $id ($name)";
      next;
    }

    # Execute
    my $result;
    if (exists $fortnox_customers{$id}) {
      say "Updating customer $id: $name";
      $result = $fortnox->putCustomer($id, $data);
    } else {
      say "Creating customer $id: $name";
      $result = $fortnox->postCustomer($data);
    }

    if (ref($result) eq 'HASH' && exists($result->{error}) && $result->{error}) {
      say "  Error: " . ($result->{message} // 'Unknown error');
    } else {
      say "  OK";
      $processed++;
    }
  }

  say "\nSummary: processed $processed, skipped $skipped";
}


sub _update_invoice ($self, $opts) {
  my $fortnox = $self->app->fortnox;
  my $invoice = $self->app->invoice;
  my $customer_model = $self->app->customer;
  my $config  = $self->app->config;

  # Convert local invoice number (YYYYXXXXX) to Fortnox format (YYXXXX for 2022 and earlier)
  # Local: YYYY + XXXXX (4-digit year + 5-digit sequence) = 9 digits
  # Fortnox: YY + XXXX (2-digit year + 4-digit sequence) = 6 digits
  my $to_fortnox_number = sub ($local_num) {
    return $local_num if length($local_num) != 9;  # Already short format or different
    my $year = substr($local_num, 0, 4);
    return $local_num if $year > 2022;  # 2023+ uses same format
    # Convert 202200001 -> 220001
    my $yy = substr($local_num, 2, 2);     # "22" from "2022"
    my $seq = substr($local_num, 5);        # "0001" from "00001" (last 4 digits)
    return $yy . $seq;
  };

  # Build ID list to process
  my @ids;
  if ($opts->{invoiceid}) {
    @ids = ($opts->{invoiceid});
  } elsif ($opts->{from}) {
    my $from_id = $opts->{from};
    my $to_id   = $opts->{to} // $from_id;
    @ids = ($from_id .. $to_id);
  } else {
    say "Error: Must specify --invoiceid or --from";
    return;
  }

  # Get existing Fortnox invoices for comparison
  say "Fetching Fortnox invoice list...";
  my %fortnox_invoices;
  my $page = 1;
  while (my $result = $fortnox->getInvoice(0, { qp => { page => $page, limit => 500 } })) {
    last if (ref($result) ne 'HASH' || !exists($result->{Invoices}));
    for my $fi (@{ $result->{Invoices} }) {
      $fortnox_invoices{ $fi->{DocumentNumber} } = $fi;
    }
    $page++;
  }
  say "Found " . scalar(keys %fortnox_invoices) . " invoices in Fortnox";

  # Cache customer data
  my %customer_cache;
  my $eucountries = join('|', $customer_model->eucountries);

  my $processed = 0;
  my $skipped   = 0;
  my $pdf_uploaded = 0;

  for my $id (@ids) {
    # Get local invoice by fakturanummer
    my $invoices = $invoice->get({ where => { fakturanummer => $id } });
    unless ($invoices && @$invoices) {
      say "Invoice $id not found locally, skipping";
      $skipped++;
      next;
    }
    my $local = $invoices->[0];

    # Convert to Fortnox number format (2022 and earlier use YYXXXXX)
    my $fortnox_id = $to_fortnox_number->($id);

    # Get customer data
    my $cust;
    if (exists $customer_cache{ $local->{customerid} }) {
      $cust = $customer_cache{ $local->{customerid} };
    } else {
      my $custs = $customer_model->get({ where => { customerid => $local->{customerid} } });
      $cust = $custs->[0] if $custs && @$custs;
      $customer_cache{ $local->{customerid} } = $cust;
    }

    my $remote = $fortnox_invoices{$fortnox_id};

    # Prompt mode: show comparison
    if ($opts->{prompt}) {
      say "\n" . "=" x 60;
      say "Invoice $id" . ($fortnox_id ne $id ? " (Fortnox: $fortnox_id)" : "");
      say "=" x 60;

      if ($remote) {
        say "\nLocal vs Remote:";
        say sprintf("  %-20s: %-30s | %-30s", "Customer", $local->{customerid}, $remote->{CustomerNumber} // '');
        say sprintf("  %-20s: %-30s | %-30s", "Date", substr($local->{invoicedate} // '', 0, 10), $remote->{InvoiceDate} // '');
        say sprintf("  %-20s: %-30s | %-30s", "Total", $local->{totalcost} // '', $remote->{Total} // '');
        say sprintf("  %-20s: %-30s | %-30s", "Currency", uc($local->{currency} // ''), $remote->{Currency} // '');
        say "\nInvoice exists in Fortnox.";
        say $opts->{pdfonly} ? "Action: Upload PDF only" : "Action: Skip (already exists)";
      } else {
        say "\nLocal data:";
        say sprintf("  %-20s: %s", "Customer", $local->{customerid});
        say sprintf("  %-20s: %s", "Date", substr($local->{invoicedate} // '', 0, 10));
        say sprintf("  %-20s: %s", "Total", $local->{totalcost} // '');
        say sprintf("  %-20s: %s", "Currency", uc($local->{currency} // ''));
        say "\nAction: CREATE invoice and upload PDF";
      }

      # Check if PDF exists
      my $pdf_path = sprintf('%s/%s.pdf',
        $config->{manager}->{invoice}->{invoicedir},
        $local->{uuid}
      );
      say sprintf("  %-20s: %s", "PDF exists", (-f $pdf_path ? 'Yes' : 'NO'));

      print "\nProceed? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }
    }

    # PDF path
    my $pdf_path = sprintf('%s/%s.pdf',
      $config->{manager}->{invoice}->{invoicedir},
      $local->{uuid}
    );

    # Dry run
    if ($opts->{dry_run}) {
      my $id_str = $id . ($fortnox_id ne $id ? " (Fortnox: $fortnox_id)" : "");
      if ($remote) {
        if ($opts->{pdfonly} || 1) {
          say "DRY RUN: Would upload PDF for invoice $id_str";
        }
      } else {
        say "DRY RUN: Would CREATE invoice $id_str and upload PDF";
      }
      next;
    }

    # PDF only mode or invoice already exists
    if ($opts->{pdfonly} || $remote) {
      if (-f $pdf_path) {
        say "Uploading PDF for invoice $id" . ($fortnox_id ne $id ? " (Fortnox: $fortnox_id)" : "") . "...";
        my $upload_result = $self->_upload_invoice_pdf($fortnox_id, $local, $pdf_path, $opts->{force});
        if ($upload_result) {
          say "  PDF uploaded and attached OK";
          $pdf_uploaded++;
        } else {
          say "  PDF upload failed";
        }
      } else {
        say "PDF not found for invoice $id: $pdf_path";
      }
      $processed++;
      next;
    }

    # Create invoice in Fortnox
    say "Creating invoice $id" . ($fortnox_id ne $id ? " (Fortnox: $fortnox_id)" : "") . " in Fortnox...";

    # Build invoice rows
    my $invoiceitems = $invoice->invoiceitems({ where => { 'invoiceitem.invoiceid' => $local->{invoiceid} } });
    my @rows;
    for my $itemid (sort { $a <=> $b } keys %$invoiceitems) {
      my $item = $invoiceitems->{$itemid};

      # Determine article number based on item text and customer country
      my $articlenumber = 3010;
      if ($item->{invoiceitemtext} =~ /snapback/i) {
        $articlenumber = 3011;
      } elsif ($item->{invoiceitemtext} =~ /dom/i) {
        $articlenumber = 3010;
      } elsif ($item->{invoiceitemtext} =~ /Rymdweb/i) {
        $articlenumber = 3012;
      }

      # Fortnox handles VAT/account mapping based on customer country and VAT number
      if ($item->{invoiceitemtext} =~ /faktura/i) {
        $articlenumber = 3540;
      }

      push @rows, {
        VAT               => 100 * ($item->{vat} // 0),
        ArticleNumber     => $articlenumber,
        Description       => $item->{invoiceitemtext},
        DeliveredQuantity => $item->{number} // 1,
        Price             => $item->{price} // 0,
      };
    }

    # Calculate rounding diff (öresavrundning for SEK only)
    # SEK rounds to whole numbers, EUR keeps 2 decimals (no bookkeeping needed)
    if (uc($local->{currency} // 'SEK') eq 'SEK') {
      my %items_for_calc = map { $_ => { %{$invoiceitems->{$_}}, include => 1 } } keys %$invoiceitems;
      my $amounts = $invoice->calculate_amounts(\%items_for_calc, $local->{vat}, $local->{currency});

      # Add rounding row if there's a diff
      if ($amounts->{diff} && $amounts->{diff} != 0) {
        push @rows, {
          VAT               => 0,
          ArticleNumber     => 3740,
          Description       => 'Öresavrundning',
          DeliveredQuantity => 1,
          Price             => $amounts->{diff},
        };
      }
    }

    my $fortnox_invoice = {
      Invoice => {
        CustomerNumber            => $local->{customerid},
        InvoiceDate               => substr($local->{invoicedate} // '', 0, 10),
        Currency                  => uc($local->{currency} // 'SEK'),
        DocumentNumber            => $fortnox_id,
        InvoiceType               => 'INVOICE',
        InvoiceRows               => \@rows,
        Language                  => uc(substr($cust->{lang} // 'sv', 0, 2)),
        ExternalInvoiceReference1 => $id,  # Keep full local number as reference
        ExternalInvoiceReference2 => $local->{uuid},
      }
    };

    # Handle credit invoices
    if ($local->{kreditfakturaavser}) {
      $fortnox_invoice->{Invoice}{CreditInvoiceReference} = $to_fortnox_number->($local->{kreditfakturaavser});
    }

    my $result = $fortnox->postInvoice($fortnox_invoice);

    if (ref($result) eq 'HASH' && exists($result->{error}) && $result->{error}) {
      say "  Error creating invoice: " . ($result->{message} // 'Unknown error');
    } elsif ($result->{Invoice} && $result->{Invoice}{DocumentNumber} == $fortnox_id) {
      say "  Invoice created OK";

      # Mark as external
      $fortnox->externalInvoice($fortnox_id);

      # Upload PDF
      if (-f $pdf_path) {
        say "  Uploading PDF...";
        my $upload_result = $self->_upload_invoice_pdf($fortnox_id, $local, $pdf_path, $opts->{force});
        if ($upload_result) {
          say "  PDF uploaded and attached OK";
          $pdf_uploaded++;
        } else {
          say "  PDF upload failed";
        }
      } else {
        say "  PDF not found: $pdf_path";
      }

      $processed++;
    } else {
      say "  Unexpected result: " . Dumper($result);
    }

    # Rate limit
    sleep 1;
  }

  say "\nSummary: processed $processed, skipped $skipped, PDFs uploaded $pdf_uploaded";
}


sub _upload_invoice_pdf ($self, $invoice_number, $local_invoice, $pdf_path, $force = 0) {
  my $fortnox = $self->app->fortnox;

  # Determine entity type: F for invoice, C for credit invoice
  my $entitytype = $local_invoice->{kreditfakturaavser} ? 'C' : 'F';

  # Check if attachment already exists
  my $existing = $fortnox->attachment('GET', undef, $invoice_number, $entitytype);
  if (ref($existing) eq 'ARRAY' && @$existing) {
    if ($force) {
      # Delete existing attachments
      for my $att (@$existing) {
        my $file_id = $att->{fileId} // $att->{FileId};
        if ($file_id) {
          say "    Deleting existing attachment $file_id...";
          $fortnox->attachment('DELETE', $file_id, $invoice_number, $entitytype);
        }
      }
    } else {
      say "    Attachment already exists, skipping (use --force to replace)";
      return 1;
    }
  }

  # Upload to inbox
  my $res = $fortnox->postInbox($pdf_path);

  # Check if response is valid
  unless (ref($res) eq 'HASH') {
    say "    Error uploading to inbox: Invalid response (got: " . (defined $res ? "'$res'" : 'undef') . ")";
    return 0;
  }

  if (exists($res->{error}) && $res->{error}) {
    say "    Error uploading to inbox: " . ($res->{message} // 'Unknown error');
    return 0;
  }

  unless (exists($res->{File}) && exists($res->{File}->{ArchiveFileId})) {
    say "    Error: No ArchiveFileId in response";
    return 0;
  }

  my $fileid = $res->{File}->{ArchiveFileId};

  # Attach to invoice
  my $attach_res = $fortnox->attachment('POST', $fileid, $invoice_number, $entitytype);

  # Attachment API returns an ARRAY on success, HASH on error
  if (ref($attach_res) eq 'ARRAY') {
    return 1;  # Success
  }

  if (ref($attach_res) eq 'HASH' && $attach_res->{error}) {
    say "    Error attaching file: " . ($attach_res->{message} // 'Unknown error');
    return 0;
  }

  # Unexpected response
  say "    Error attaching file: Unexpected response";
  return 0;
}


sub _create_accounts ($self, $opts) {
  my $fortnox = $self->app->fortnox;

  # Build list of accounts to process
  my @accounts_to_process;
  if ($opts->{number}) {
    my ($account) = grep { $_->{Number} eq $opts->{number} } @{ $self->accounts };
    unless ($account) {
      say "Account $opts->{number} not found in predefined list";
      say "Available accounts:";
      for my $a (@{ $self->accounts }) {
        say "  $a->{Number}: $a->{Description}";
      }
      return;
    }
    @accounts_to_process = ($account);
  } elsif ($opts->{all}) {
    @accounts_to_process = @{ $self->accounts };
  } else {
    say "Error: Must specify --all or --number=NUMBER";
    say "Available accounts:";
    for my $a (@{ $self->accounts }) {
      say "  $a->{Number}: $a->{Description}";
    }
    return;
  }

  say "Checking/creating " . scalar(@accounts_to_process) . " account(s)...";

  my $created = 0;
  my $exists  = 0;
  my $errors  = 0;

  for my $account (@accounts_to_process) {
    my $number = $account->{Number};

    # Check if account exists
    my $existing = $fortnox->getAccount($number);

    if (ref($existing) eq 'HASH' && $existing->{Account}) {
      say "Account $number already exists: $existing->{Account}->{Description}";
      $exists++;
      next;
    }

    # Account doesn't exist, create it
    if ($opts->{dry_run}) {
      say "DRY RUN: Would create account $number: $account->{Description}";
      next;
    }

    say "Creating account $number: $account->{Description}";

    my $payload = {
      Account => {
        Number      => $number,
        Description => $account->{Description},
        SRU         => $account->{SRU},
        VATCode     => $account->{VATCode},
      }
    };

    my $result = $fortnox->postAccount($payload);

    if (ref($result) eq 'HASH' && $result->{Account}) {
      say "  OK";
      $created++;
    } elsif (ref($result) eq 'HASH' && ($result->{error} || $result->{ErrorInformation})) {
      my $msg = $result->{ErrorInformation}->{message} // $result->{message} // 'Unknown error';
      say "  Error: $msg";
      $errors++;
    } else {
      say "  Unexpected response";
      $errors++;
    }

    # Rate limit
    sleep 1;
  }

  say "\nSummary: created $created, already existed $exists, errors $errors";
}


sub _update_accounts ($self, $opts) {
  my $fortnox = $self->app->fortnox;

  # Build list of accounts to process
  my @accounts_to_process;
  if ($opts->{number}) {
    my ($account) = grep { $_->{Number} eq $opts->{number} } @{ $self->accounts };
    unless ($account) {
      say "Account $opts->{number} not found in predefined list";
      say "Available accounts:";
      for my $a (@{ $self->accounts }) {
        say "  $a->{Number}: $a->{Description}";
      }
      return;
    }
    @accounts_to_process = ($account);
  } elsif ($opts->{all}) {
    @accounts_to_process = @{ $self->accounts };
  } else {
    say "Error: Must specify --all or --number=NUMBER";
    say "Available accounts:";
    for my $a (@{ $self->accounts }) {
      say "  $a->{Number}: $a->{Description}";
    }
    return;
  }

  say "Checking/updating " . scalar(@accounts_to_process) . " account(s)...";

  my $created  = 0;
  my $updated  = 0;
  my $skipped  = 0;
  my $errors   = 0;

  for my $account (@accounts_to_process) {
    my $number = $account->{Number};

    # Check if account exists
    my $existing = $fortnox->getAccount($number);

    if (ref($existing) eq 'HASH' && $existing->{Account}) {
      my $remote = $existing->{Account};

      # Compare fields
      my @diffs;
      push @diffs, ['Description', $account->{Description}, $remote->{Description}]
        if ($account->{Description} // '') ne ($remote->{Description} // '');
      push @diffs, ['SRU', $account->{SRU}, $remote->{SRU}]
        if ($account->{SRU} // '') ne ($remote->{SRU} // '');
      push @diffs, ['VATCode', $account->{VATCode}, $remote->{VATCode}]
        if ($account->{VATCode} // '') ne ($remote->{VATCode} // '');

      unless (@diffs) {
        say "Account $number: no changes";
        $skipped++;
        next;
      }

      # Show differences and prompt
      say "\n" . "=" x 60;
      say "Account $number: $account->{Description}";
      say "=" x 60;
      say "\nDifferences (Local | Remote):";
      for my $diff (@diffs) {
        say sprintf("  %-15s: %-25s | %-25s", $diff->[0], $diff->[1] // '', $diff->[2] // '');
      }

      if ($opts->{dry_run}) {
        say "DRY RUN: Would update account $number";
        next;
      }

      print "\nUpdate? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }

      # Update account
      say "Updating account $number...";
      my $payload = {
        Account => {
          Number      => $number,
          Description => $account->{Description},
          SRU         => $account->{SRU},
          VATCode     => $account->{VATCode},
        }
      };

      my $result = $fortnox->putAccount($number, $payload);

      if (ref($result) eq 'HASH' && $result->{Account}) {
        say "  OK";
        $updated++;
      } elsif (ref($result) eq 'HASH' && ($result->{error} || $result->{ErrorInformation})) {
        my $msg = $result->{ErrorInformation}->{message} // $result->{message} // 'Unknown error';
        say "  Error: $msg";
        $errors++;
      } else {
        say "  Unexpected response";
        $errors++;
      }
    } else {
      # Account doesn't exist - prompt to create
      say "\n" . "=" x 60;
      say "Account $number: $account->{Description}";
      say "=" x 60;
      say "\nAccount does not exist in Fortnox.";
      say sprintf("  %-15s: %s", "Description", $account->{Description});
      say sprintf("  %-15s: %s", "SRU", $account->{SRU});
      say sprintf("  %-15s: %s", "VATCode", $account->{VATCode});

      if ($opts->{dry_run}) {
        say "DRY RUN: Would create account $number";
        next;
      }

      print "\nCreate? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }

      # Create account
      say "Creating account $number...";
      my $payload = {
        Account => {
          Number      => $number,
          Description => $account->{Description},
          SRU         => $account->{SRU},
          VATCode     => $account->{VATCode},
        }
      };

      my $result = $fortnox->postAccount($payload);

      if (ref($result) eq 'HASH' && $result->{Account}) {
        say "  OK";
        $created++;
      } elsif (ref($result) eq 'HASH' && ($result->{error} || $result->{ErrorInformation})) {
        my $msg = $result->{ErrorInformation}->{message} // $result->{message} // 'Unknown error';
        say "  Error: $msg";
        $errors++;
      } else {
        say "  Unexpected response";
        $errors++;
      }
    }

    # Rate limit
    sleep 1;
  }

  say "\nSummary: created $created, updated $updated, skipped $skipped, errors $errors";
}


sub _update_article ($self, $opts) {
  my $fortnox = $self->app->fortnox;

  # Build list of articles to process
  my @articles_to_process;
  if ($opts->{articleid}) {
    my ($article) = grep { $_->{ArticleNumber} eq $opts->{articleid} } @{ $self->articles };
    unless ($article) {
      say "Article $opts->{articleid} not found in predefined list";
      say "Available articles:";
      for my $a (@{ $self->articles }) {
        say "  $a->{ArticleNumber}: $a->{Description}";
      }
      return;
    }
    @articles_to_process = ($article);
  } elsif ($opts->{all}) {
    @articles_to_process = @{ $self->articles };
  } else {
    say "Error: Must specify --all or --articleid=ARTICLENUMBER";
    say "Available articles:";
    for my $a (@{ $self->articles }) {
      say "  $a->{ArticleNumber}: $a->{Description}";
    }
    return;
  }

  say "Checking/updating " . scalar(@articles_to_process) . " article(s)...";

  my $created  = 0;
  my $updated  = 0;
  my $skipped  = 0;
  my $errors   = 0;

  for my $article (@articles_to_process) {
    my $article_number = $article->{ArticleNumber};

    # Check if article exists (use API, not hardcoded getArticle)
    my $existing = $fortnox->callAPI('Articles', 'get', $article_number);

    if (ref($existing) eq 'HASH' && $existing->{Article}) {
      my $remote = $existing->{Article};

      # Compare fields
      my @diffs;
      push @diffs, ['Description', $article->{Description}, $remote->{Description}]
        if ($article->{Description} // '') ne ($remote->{Description} // '');
      push @diffs, ['Type', $article->{Type}, $remote->{Type}]
        if ($article->{Type} // '') ne ($remote->{Type} // '');
      push @diffs, ['VAT', $article->{VAT}, $remote->{VAT}]
        if ($article->{VAT} // '') ne ($remote->{VAT} // '');
      push @diffs, ['SalesAccount', $article->{SalesAccount}, $remote->{SalesAccount}]
        if ($article->{SalesAccount} // '') ne ($remote->{SalesAccount} // '');
      push @diffs, ['EUVATAccount', $article->{EUVATAccount}, $remote->{EUVATAccount}]
        if ($article->{EUVATAccount} // '') ne ($remote->{EUVATAccount} // '');
      push @diffs, ['ExportAccount', $article->{ExportAccount}, $remote->{ExportAccount}]
        if ($article->{ExportAccount} // '') ne ($remote->{ExportAccount} // '');
      push @diffs, ['EUAccount', $article->{EUAccount}, $remote->{EUAccount}]
        if ($article->{EUAccount} // '') ne ($remote->{EUAccount} // '');

      unless (@diffs) {
        say "Article $article_number: no changes";
        $skipped++;
        next;
      }

      # Show differences and prompt
      say "\n" . "=" x 60;
      say "Article $article_number: $article->{Description}";
      say "=" x 60;
      say "\nDifferences (Local | Remote):";
      for my $diff (@diffs) {
        say sprintf("  %-15s: %-25s | %-25s", $diff->[0], $diff->[1] // '', $diff->[2] // '');
      }

      if ($opts->{dry_run}) {
        say "DRY RUN: Would update article $article_number";
        next;
      }

      print "\nUpdate? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }

      # Update article
      say "Updating article $article_number...";
      my $payload = {
        Article => {
          ArticleNumber => $article_number,
          Description   => $article->{Description},
          Type          => $article->{Type},
          VAT           => $article->{VAT},
          SalesAccount  => $article->{SalesAccount},
          EUVATAccount  => $article->{EUVATAccount},
          ExportAccount => $article->{ExportAccount},
          EUAccount     => $article->{EUAccount},
        }
      };

      my $result = $fortnox->callAPI('Articles', 'put', $article_number, $payload);

      if (ref($result) eq 'HASH' && $result->{Article}) {
        say "  OK";
        $updated++;
      } elsif (ref($result) eq 'HASH' && ($result->{error} || $result->{ErrorInformation})) {
        my $msg = $result->{ErrorInformation}->{message} // $result->{message} // 'Unknown error';
        say "  Error: $msg";
        $errors++;
      } else {
        say "  Unexpected response";
        $errors++;
      }
    } else {
      # Article doesn't exist - prompt to create
      say "\n" . "=" x 60;
      say "Article $article_number: $article->{Description}";
      say "=" x 60;
      say "\nArticle does not exist in Fortnox.";
      say sprintf("  %-15s: %s", "Description", $article->{Description});
      say sprintf("  %-15s: %s", "Type", $article->{Type});
      say sprintf("  %-15s: %s", "VAT", $article->{VAT});
      say sprintf("  %-15s: %s", "SalesAccount", $article->{SalesAccount});
      say sprintf("  %-15s: %s", "EUVATAccount", $article->{EUVATAccount});
      say sprintf("  %-15s: %s", "ExportAccount", $article->{ExportAccount});
      say sprintf("  %-15s: %s", "EUAccount", $article->{EUAccount});

      if ($opts->{dry_run}) {
        say "DRY RUN: Would create article $article_number";
        next;
      }

      print "\nCreate? [y/N/q] ";
      my $answer = <STDIN>;
      chomp $answer;
      if (lc($answer) eq 'q') {
        say "Quitting...";
        last;
      }
      unless (lc($answer) eq 'y') {
        say "Skipped";
        $skipped++;
        next;
      }

      # Create article
      say "Creating article $article_number...";
      my $payload = {
        Article => {
          ArticleNumber => $article_number,
          Description   => $article->{Description},
          Type          => $article->{Type},
          VAT           => $article->{VAT},
          SalesAccount  => $article->{SalesAccount},
          EUVATAccount  => $article->{EUVATAccount},
          ExportAccount => $article->{ExportAccount},
          EUAccount     => $article->{EUAccount},
        }
      };

      my $result = $fortnox->callAPI('Articles', 'post', 0, $payload);

      if (ref($result) eq 'HASH' && $result->{Article}) {
        say "  OK";
        $created++;
      } elsif (ref($result) eq 'HASH' && ($result->{error} || $result->{ErrorInformation})) {
        my $msg = $result->{ErrorInformation}->{message} // $result->{message} // 'Unknown error';
        say "  Error: $msg";
        $errors++;
      } else {
        say "  Unexpected response";
        $errors++;
      }
    }

    # Rate limit
    sleep 1;
  }

  say "\nSummary: created $created, updated $updated, skipped $skipped, errors $errors";
}


1;

=head1 SYNOPSIS

  Usage: samizdat fortnox <subcommand> <resource> [OPTIONS]

  Subcommands:
    update customer     Sync customers to Fortnox
    update invoice      Sync invoices to Fortnox (with PDF upload)
    update accounts     Update bookkeeping accounts in Fortnox (interactive)
    update article      Update articles/products in Fortnox (interactive)
    create accounts     Create bookkeeping accounts in Fortnox (if not exist)

  Customer options:
    --customerid=ID     Update single customer by ID
    --from=ID           Start of customer ID range
    --to=ID             End of customer ID range (optional, defaults to --from)

  Invoice options:
    --invoiceid=ID      Update single invoice by fakturanummer
    --from=ID           Start of invoice number range
    --to=ID             End of invoice number range (optional, defaults to --from)
    --pdfonly           Only upload PDFs for existing invoices (don't create)
    --force             Replace existing PDF attachments

  Accounts options:
    --all               Process all predefined accounts
    --number=NUMBER     Process single account by number (e.g., 3010)

  Article options:
    --all               Process all predefined articles
    --articleid=NUMBER  Process single article by number (e.g., 3010)

  Common options:
    --prompt            Interactive mode: show local vs remote data and confirm
    --dry-run           Show what would be done without doing it
    -h, --help          Show this help

  Examples:
    # Update single customer
    samizdat fortnox update customer --customerid=1234

    # Update customer range with prompting
    samizdat fortnox update customer --from=1000 --to=1100 --prompt

    # Upload PDFs for invoice range (invoices already exist in Fortnox)
    samizdat fortnox update invoice --from=202300001 --to=202312999 --pdfonly

    # Create invoices and upload PDFs interactively
    samizdat fortnox update invoice --from=202400001 --to=202400100 --prompt

    # Dry run to see what would happen
    samizdat fortnox update invoice --from=202300001 --to=202300010 --dry-run

    # Create all predefined accounts (skip existing)
    samizdat fortnox create accounts --all

    # Create single account
    samizdat fortnox create accounts --number=3010

    # Dry run to see what accounts would be created
    samizdat fortnox create accounts --all --dry-run

    # Update accounts interactively (prompt for each difference)
    samizdat fortnox update accounts --all

    # Update single account
    samizdat fortnox update accounts --number=3010

    # Update all predefined articles interactively
    samizdat fortnox update article --all

    # Update single article
    samizdat fortnox update article --articleid=3010

    # Dry run to see what articles would be created/updated
    samizdat fortnox update article --all --dry-run

=cut
