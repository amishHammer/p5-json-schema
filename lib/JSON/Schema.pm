package JSON::Schema;

sub new
{
	my ($class, $schema) = @_;
	return bless {schema=>$schema}, $class;
}

sub schema
{
	my ($self) = @_;
	return $self->{'schema'};
}

sub validate
{
	my ($self, $object) = @_;
	my $helper = JSON::Schema::Helper->new;
	my $result = $helper->validate($object, $self->schema);
	return JSON::Schema::Result->new($result);
}

1;

package JSON::Schema::Result;

use overload bool => \&valid;

sub new
{
	my ($class, $result) = @_;
	return bless $result, $class;
}

sub valid
{
	my ($self) = @_;
	return $self->{'valid'};
}

sub errors
{
	my ($self) = @_;
	return map { JSON::Schema::Error->new($_); } @{$self->{'errors'}};
}

1;

package JSON::Schema::Error;

use overload '""' => \&to_string;

sub new
{
	my ($class, $e) = @_;
	return bless $e, $class;
}

sub property
{
	my ($self) = @_;
	return $self->{property};
}

sub message
{
	my ($self) = @_;
	return $self->{message};
}

sub to_string
{
	my ($self) = @_;
	return sprintf("%s: %s", $self->property, $self->message);
}

1;

package JSON::Schema::Helper;

### 
 # JSONSchema Validator - Validates JavaScript objects using JSON Schemas 
 #	(http://www.json.com/json-schema-proposal/)
 #
 # Copyright (c) 2007 Kris Zyp SitePen (www.sitepen.com)
 # Licensed under the MIT (MIT-LICENSE.txt) license.
#To use the validator call JSONSchema.validate with an instance object and an optional schema object.
#If a schema is provided, it will be used to validate. If the instance object refers to a schema (self-validating), 
#that schema will be used to validate and the schema parameter is not necessary (if both exist, 
#both validations will occur). 
#The validate method will return an array of validation errors. If there are no errors, then an 
#empty list will be returned. A validation error will have two properties: 
#"property" which indicates which property had the error
#"message" which indicates what the error was
 ##

use common::sense;
use constant FALSE => 0;
use constant TRUE  => 1;

use Scalar::Util qw[blessed];

sub new
{
	my ($class) = @_;
	return bless { errors=>[] }, $class;
}

sub validate
{
	my ($self, $instance, $schema) = @_;
	## Summary:
	##  	To use the validator call JSONSchema.validate with an instance object and an optional schema object.
	## 		If a schema is provided, it will be used to validate. If the instance object refers to a schema (self-validating), 
	## 		that schema will be used to validate and the schema parameter is not necessary (if both exist, 
	## 		both validations will occur). 
	## 		The validate method will return an object with two properties:
	## 			valid: A boolean indicating if the instance is valid by the schema
	## 			errors: An array of validation errors. If there are no errors, then an 
	## 					empty list will be returned. A validation error will have two properties: 
	## 						property: which indicates which property had the error
	## 						message: which indicates what the error was
	##
	return $self->_validate($instance, $schema, FALSE);
}

sub checkPropertyChange
{
	my ($self, $value, $schema, $property) = @_;
	## Summary:
	## 		The checkPropertyChange method will check to see if an value can legally be in property with the given schema
	## 		This is slightly different than the validate method in that it will fail if the schema is readonly and it will
	## 		not check for self-validation, it is assumed that the passed in value is already internally valid.  
	## 		The checkPropertyChange method will return the same object type as validate, see JSONSchema.validate for 
	## 		information.
	##
	return $self->_validate($value, $schema, $property||'property');	
}

sub _validate
{
	my ($self, $instance, $schema, $_changing) = @_;
	
	$self->{errors} = [];
	
	if ($schema)
	{
		$self->checkProp($instance, $schema, '', $_changing || '', $_changing);
	}
	if(!$_changing and defined $instance and defined $instance->{'$schema'})
	{
		$self->checkProp($instance, $instance->{'$schema'}, '', '', $_changing);
	}
	
	return { valid=>(@{$self->{errors}} ? FALSE : TRUE), errors=> $self->{errors} };
}

sub checkType
{
	my ($self, $type, $value, $path, $_changing) = @_;
	if ($type)
	{
#		if (ref $type ne 'HASH'
#		and $type ne 'any'
#		and ($type eq 'null' ? $self->jsIsNull($value) : $self->jsMatchType($type, $value))
#		and !(ref $value eq 'ARRAY' and $type eq 'array')
#		and !($type eq 'integer' and $value % 1 == 0))
		if (!$self->jsMatchType($type, $value))
		{
			return ({ property=>$path, message=>$self->jsGuessType($value)." value found, but a $type is required" });
		}
		if (ref $type eq 'ARRAY')
		{
			my @unionErrors;
			TYPE: foreach my $t (@$type)
			{
				@unionErrors = @{ $self->checkType($t, $value, $path, $_changing) };
				last unless @unionErrors;
			}
			return @unionErrors if @unionErrors;
		}
		elsif (ref $type eq 'HASH')
		{
			local $self->{errors} = [];
			checkProp($value, $type, $path, undef, $_changing);
			return @{ $self->{errors} };
		}
	}
	return;
}

# validate a value against a property definition
sub checkProp
{
	my ($self, $value, $schema, $path, $i, $_changing) = @_;
	my $l;
	$path .= $path ? ( ref $value eq 'ARRAY' ? "[${i}]" : ".${i}") : "\$${i}";
	
	my $addError = sub
	{
		my ($message) = @_;
		push @{$self->{errors}}, { property=>$path, message=>$message };
	};
	
	if (ref $schema ne 'HASH' and ($path or ref $schema ne 'CODE'))
	{
		if (ref $schema eq 'CODE')
		{
			# ~TOBYINK: I don't think this makes any sense in Perl
			$addError->("is not an instance of the class/constructor " . $schema);
		}
		elsif ($schema)
		{
			$addError->("Invalid schema/property definition " . $schema);
		}
		return undef;
	}
	if ($_changing and $schema->{'readonly'})
	{
		$addError->("is a readonly field, it can not be changed");
	}
	if ($schema->{'extends'})
	{
		checkProp($value, $schema->{'extends'}, $path, $i, $_changing);
	}
	
	# validate a value against a type definition
	if (!defined $value)
	{
		$addError->("is missing and it is not optional")
			unless $schema->{'optional'};
	}
	else
	{
		push @{$self->{errors}}, $self->checkType($schema->{'type'}, $value, $path, $_changing);
		if (defined $schema->{'disallow'}
		and !$self->checkType($schema->{'disallow'}, $value, $path, $_changing))
		{
			$addError->(" disallowed value was matched");
		}
		if (!$self->jsIsNull($value))
		{
			if (ref $value eq 'ARRAY')
			{
				if (ref $schema->{'items'} eq 'ARRAY')
				{
					for (my $i=0; $i < scalar @{ $schema->{'items'} }; $i++)
					{
						my $x = defined $value->[$i] ? $value->[$i] : JSON::Schema::Null->new; 
						push @{$self->{errors}}, checkProp($x, $schema->{'items'}->[$i], $path, $i, $_changing);
					}
				}
				elsif (defined $schema->{'items'})
				{
					for (my $i=0; $i < scalar @{ $schema->{'items'} }; $i++)
					{
						my $x = defined $value->[$i] ? $value->[$i] : JSON::Schema::Null->new; 
						push @{$self->{errors}}, checkProp($x, $schema->{'items'}, $path, $i, $_changing);
					}
				}
				if ($schema->{'minItems'}
				and scalar @$value < $schema->{'minItems'})
				{
					addError->("There must be a minimum of " . $schema->{'minItems'} . " in the array");
				}
				if ($schema->{'maxItems'}
				and scalar @$value > $schema->{'maxItems'})
				{
					addError->("There must be a maximum of " . $schema->{'maxItems'} . " in the array");
				}
			}
			elsif ($schema->{'properties'})
			{
				push @{$self->{errors}}, $self->checkObj($value, $schema->{'properties'}, $path, $schema->{'additionalProperties'}, $_changing);
			}
			if ($schema->{'pattern'} and $self->jsMatchType('string', $value))
			{
				my $x = $schema->{'pattern'};
				$addError->("does not match the regex pattern $x")
					unless $value =~ /$x/;
			}
			if ($schema->{'maxLength'} and $self->jsMatchType('string', $value)
			and strlen($value) > $schema->{'maxLength'})
			{
				$addError->("may only be " . $schema->{'maxLength'} . " characters long");
			}
			if ($schema->{'minLength'} and $self->jsMatchType('string', $value)
			and strlen($value) < $schema->{'minLength'})
			{
				$addError->("must be at least " . $schema->{'minLength'} . " characters long");
			}
			if (defined $schema->{'minimum'} and $self->jsMatchType('string', $value))
			{
				$addError->("must have a minimum value of '" . $schema->{'minimum'}) . "'"
					if $value lt $schema->{'minimum'};
			}
			elsif (defined $schema->{'minimum'})
			{
				$addError->("must have a minimum value of " . $schema->{'minimum'})
					if $value < $schema->{'minimum'};
			}
			if (defined $schema->{'maximum'} and $self->jsMatchType('string', $value))
			{
				$addError->("must have a maximum value of '" . $schema->{'maximum'}) . "'"
					if $value lt $schema->{'maximum'};
			}
			elsif (defined $schema->{'maximum'})
			{
				$addError->("must have a maximum value of " . $schema->{'maximum'})
					if $value < $schema->{'maximum'};
			}
			if ($schema->{'enum'})
			{
				$addError->("does not have a value in the enumeration {" . (join ",", @{ $schema->{'enum'} }) . '}')
					unless grep { $value eq $_ } @{ $schema->{'enum'} };
			}
			if ($schema->{'maxDecimal'})
			{
				my $regexp = "\\.[0-9]{" . ($schema->{'maxDecimal'} + 1) . ",}";
				$addError->("may only have " . $schema->{'maxDecimal'} . " digits of decimal places")
					if $value =~ /$regexp/;
			}
		} # END: if (!$self->jsIsNull()) { ... }
	} # END: if (!$defined $value) {} else {...}
	return;
}; # END: sub checkProp


sub checkObj
{
	my ($self, $instance, $objTypeDef, $path, $additionalProp, $_changing) = @_;
	my @errors;
	
	if (ref $objTypeDef eq 'HASH')
	{
		if (ref $instance ne 'HASH')
		{
			push @errors, {property=>$path, message=>"an object is required"};
		}
		
		foreach my $i (keys %$objTypeDef)
		{
			unless ($i =~ /^__/)
			{
				my $value   = defined $instance->{$i} ? $instance->{$i} : exists $instance->{$i} ? JSON::Schema::Null->new : undef;
				my $propDef = $objTypeDef->{$i};
				$self->checkProp($value, $propDef, $path, $i, $_changing);
			}
		}
	} # END: if (ref $objTypeDef eq 'HASH')
	foreach my $i (keys %$instance)
	{
		if ($i !~ /^__/
		and defined $objTypeDef
		and not defined $objTypeDef->{$i}
		and not defined $additionalProp)
		{
			push @errors, {property=>$path,message=>"The property $i is not defined in the schema and the schema does not allow additional properties"};
		}
		my $requires = $objTypeDef && $objTypeDef->{$i} && $objTypeDef->{$i}->{'requires'};
		if (defined $requires and not defined $instance->{$requires})
		{
			push @errors, {property=>$path,message=>"the presence of the property $i requires that $requires also be present"};
		}
		my $value = defined $instance->{$i} ? $instance->{$i} : exists $instance->{$i} ? JSON::Schema::Null->new : undef;
		if (defined $objTypeDef
		and ref $objTypeDef eq 'HASH'
		and !defined $objTypeDef->{$i})
		{
			$self->checkProp($value, $additionalProp, $path, $i, $_changing); 
		}
		if(!$_changing and defined $value and defined $value->{'$schema'})
		{
			push @errors, $self->checkProp($value, $value->{'$schema'}, $path, $i, $_changing);
		}
	}
	return @errors;
}

sub jsIsNull
{
	my ($self, $value) = @_;
	
	return TRUE if blessed($value) && $value->isa('JSON::Schema::Null');
	
	return FALSE;
}

sub jsMatchType
{
	my ($self, $type, $value) = @_;
	
	if (lc $type eq 'string')
	{
		return (ref $value) ? FALSE : TRUE;
	}

	if (lc $type eq 'number')
	{
		return ($value =~ /^\-?[0-9]*(\.[0-9]*)?$/) ? TRUE : FALSE;
	}
	
	if (lc $type eq 'integer')
	{
		return ($value =~ /^\-?[0-9]+$/) ? TRUE : FALSE;
	}
	
	if (lc $type eq 'boolean')
	{
		return (ref $value eq 'SCALAR' and $$value==0 and $$value==1) ? TRUE : FALSE;
	}

	if (lc $type eq 'object')
	{
		return (ref $value eq 'HASH') ? TRUE : FALSE;
	}
	
	if (lc $type eq 'array')
	{
		return (ref $value eq 'ARRAY') ? TRUE : FALSE;
	}

	if (lc $type eq 'null')
	{
		return $self->jsIsNull($value);
	}
	
	if (lc $type eq 'any')
	{
		return TRUE;
	}
	
	if (lc $type eq 'none')
	{
		return FALSE;
	}
	
	if (blessed($value) and $value->isa($type))
	{
		return TRUE;
	}
	
	return FALSE;
}

sub jsGuessType
{
	my ($self, $value) = @_;
	
	return 'object'
		if ref $value eq 'HASH';

	return 'array'
		if ref $value eq 'ARRAY';

	return 'boolean'
		if (ref $value eq 'SCALAR' and $$value==0 and $$value==1);
	
	return 'null'
		if $self->jsIsNull($value);
		
	return ref $value
		if ref $value;

	return 'integer'
		if $value =~ /^\-?[0-9]+$/;
	
	return 'number'
		if $value =~ /^\-?[0-9]*(\.[0-9]*)?$/;
	
	return 'string';
}

1;

package JSON::Schema::Null;

use overload '""' => sub { return '' };

sub new
{
	my ($class) = @_;
	my $x = '';
	return bless \$x, $class;
}

sub TO_JSON
{
	return undef;
}

1;